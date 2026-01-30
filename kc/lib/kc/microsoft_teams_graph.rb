# KC: Microsoft Graph API client for Teams Chat integration.
#
# Wraps the Graph REST API for:
#   - OAuth2 token exchange and refresh
#   - Sending / receiving chat messages
#   - Managing webhook subscriptions (create, renew, delete)
#   - Fetching user profile info
#
# Uses Zammad's built-in UserAgent for HTTP requests (no extra gems).
#
# Usage:
#   graph = Kc::MicrosoftTeamsGraph.new(
#     client_id:     '...',
#     client_secret: '...',
#     tenant_id:     '...',
#     access_token:  '...',
#     refresh_token: '...',
#   )
#   graph.send_chat_message(chat_id, 'Hello from Zammad!')
#
module Kc
  class MicrosoftTeamsGraph
    GRAPH_BASE_URL = 'https://graph.microsoft.com/v1.0'.freeze
    LOGIN_BASE_URL = 'https://login.microsoftonline.com'.freeze
    OAUTH_SCOPES   = 'offline_access openid profile email Chat.Read Chat.ReadWrite ChatMessage.Send User.Read'.freeze

    attr_reader :client_id, :client_secret, :tenant_id
    attr_accessor :access_token, :refresh_token

    def initialize(client_id:, client_secret:, tenant_id:, access_token: nil, refresh_token: nil)
      @client_id     = client_id
      @client_secret = client_secret
      @tenant_id     = tenant_id
      @access_token  = access_token
      @refresh_token = refresh_token
    end

    # ------------------------------------------------------------------
    # OAuth2 helpers
    # ------------------------------------------------------------------

    # Returns the URL to redirect the user to for OAuth consent.
    def authorize_url(redirect_uri, state)
      params = {
        client_id:     client_id,
        response_type: 'code',
        redirect_uri:  redirect_uri,
        response_mode: 'query',
        scope:         OAUTH_SCOPES,
        state:         state,
      }
      "#{LOGIN_BASE_URL}/#{tenant_id}/oauth2/v2.0/authorize?#{params.to_query}"
    end

    # Exchanges an authorization code for access + refresh tokens.
    def exchange_code(code, redirect_uri)
      url = "#{LOGIN_BASE_URL}/#{tenant_id}/oauth2/v2.0/token"
      body = {
        client_id:     client_id,
        client_secret: client_secret,
        code:          code,
        redirect_uri:  redirect_uri,
        grant_type:    'authorization_code',
        scope:         OAUTH_SCOPES,
      }
      response = post_form(url, body)
      raise "Token exchange failed: #{response[:error_description] || response[:error]}" if response[:access_token].blank?

      self.access_token  = response[:access_token]
      self.refresh_token = response[:refresh_token]
      response
    end

    # Refreshes the access token using the stored refresh token.
    def refresh_access_token!
      raise 'No refresh token available' if refresh_token.blank?

      url = "#{LOGIN_BASE_URL}/#{tenant_id}/oauth2/v2.0/token"
      body = {
        client_id:     client_id,
        client_secret: client_secret,
        refresh_token: refresh_token,
        grant_type:    'refresh_token',
        scope:         OAUTH_SCOPES,
      }
      response = post_form(url, body)
      raise "Token refresh failed: #{response[:error_description] || response[:error]}" if response[:access_token].blank?

      self.access_token  = response[:access_token]
      self.refresh_token = response[:refresh_token] if response[:refresh_token].present?
      response
    end

    # ------------------------------------------------------------------
    # Chat Messages
    # ------------------------------------------------------------------

    # Sends a message to a Teams chat.
    # Returns the created message hash.
    def send_chat_message(chat_id, body_content, content_type: 'text')
      url = "#{GRAPH_BASE_URL}/chats/#{chat_id}/messages"
      payload = {
        body: {
          contentType: content_type,
          content:     body_content,
        },
      }
      graph_post(url, payload)
    end

    # Fetches a single chat message by ID.
    def get_chat_message(chat_id, message_id)
      url = "#{GRAPH_BASE_URL}/chats/#{chat_id}/messages/#{message_id}"
      graph_get(url)
    end

    # Lists recent messages in a chat (paginated).
    # Options: top (default 50)
    def list_chat_messages(chat_id, top: 50)
      url = "#{GRAPH_BASE_URL}/chats/#{chat_id}/messages?$top=#{top}&$orderby=createdDateTime desc"
      graph_get(url)
    end

    # ------------------------------------------------------------------
    # Webhook Subscriptions
    # ------------------------------------------------------------------

    # Creates a Graph webhook subscription for new messages in a chat.
    # Returns the subscription hash (including id, expirationDateTime).
    def create_subscription(chat_id, notification_url, client_state, expiration_minutes: 55)
      url = "#{GRAPH_BASE_URL}/subscriptions"
      payload = {
        changeType:                    'created',
        notificationUrl:               notification_url,
        resource:                      "/chats/#{chat_id}/messages",
        expirationDateTime:            expiration_minutes.minutes.from_now.utc.iso8601,
        clientState:                   client_state,
        includeResourceData:           false,
        latestSupportedTlsVersion:     'v1_2',
      }
      graph_post(url, payload)
    end

    # Renews (extends) an existing subscription.
    def renew_subscription(subscription_id, expiration_minutes: 55)
      url = "#{GRAPH_BASE_URL}/subscriptions/#{subscription_id}"
      payload = {
        expirationDateTime: expiration_minutes.minutes.from_now.utc.iso8601,
      }
      graph_patch(url, payload)
    end

    # Deletes a subscription.
    def delete_subscription(subscription_id)
      url = "#{GRAPH_BASE_URL}/subscriptions/#{subscription_id}"
      graph_delete(url)
    end

    # ------------------------------------------------------------------
    # User Info
    # ------------------------------------------------------------------

    # Fetches the authenticated user's profile.
    def me
      graph_get("#{GRAPH_BASE_URL}/me")
    end

    # Fetches a user's profile by their Graph user ID.
    def get_user(user_id)
      graph_get("#{GRAPH_BASE_URL}/users/#{user_id}")
    end

    # ------------------------------------------------------------------
    # Chats
    # ------------------------------------------------------------------

    # Lists the authenticated user's chats.
    def list_chats(top: 50)
      graph_get("#{GRAPH_BASE_URL}/me/chats?$top=#{top}&$expand=members")
    end

    # Gets a single chat by ID.
    def get_chat(chat_id)
      graph_get("#{GRAPH_BASE_URL}/chats/#{chat_id}?$expand=members")
    end

    private

    # ------------------------------------------------------------------
    # HTTP helpers using Zammad's UserAgent
    # ------------------------------------------------------------------

    def graph_get(url)
      response = UserAgent.get(
        url,
        {},
        {
          headers:       auth_headers,
          json:          true,
          open_timeout:  10,
          read_timeout:  30,
          total_timeout: 60,
          log:           { facility: 'kc_teams_graph' },
        },
      )
      handle_response(response)
    end

    def graph_post(url, payload)
      response = UserAgent.post(
        url,
        payload.to_json,
        {
          headers:       auth_headers.merge('Content-Type' => 'application/json'),
          json:          true,
          open_timeout:  10,
          read_timeout:  30,
          total_timeout: 60,
          log:           { facility: 'kc_teams_graph' },
        },
      )
      handle_response(response)
    end

    def graph_patch(url, payload)
      response = UserAgent.patch(
        url,
        payload.to_json,
        {
          headers:       auth_headers.merge('Content-Type' => 'application/json'),
          json:          true,
          open_timeout:  10,
          read_timeout:  30,
          total_timeout: 60,
          log:           { facility: 'kc_teams_graph' },
        },
      )
      handle_response(response)
    end

    def graph_delete(url)
      response = UserAgent.delete(
        url,
        {},
        {
          headers:       auth_headers,
          json:          true,
          open_timeout:  10,
          read_timeout:  30,
          total_timeout: 60,
          log:           { facility: 'kc_teams_graph' },
        },
      )
      # DELETE returns 204 No Content on success
      return true if response.code.to_i == 204

      handle_response(response)
    end

    # Posts form-encoded data (for OAuth token endpoints).
    # Does NOT use json: true because that would encode the request body
    # as JSON; OAuth token endpoints require application/x-www-form-urlencoded.
    # Manually parses the JSON response, matching Zammad's upstream
    # ExternalCredential::MicrosoftBase pattern.
    def post_form(url, body)
      response = UserAgent.post(
        url,
        body,
        {
          open_timeout:  10,
          read_timeout:  30,
          total_timeout: 60,
          log:           { facility: 'kc_teams_graph' },
        },
      )

      if response.code.to_i != 200 && response.body.blank?
        raise "Token request failed (HTTP #{response.code})"
      end

      result = JSON.parse(response.body).with_indifferent_access
      if result[:error].present? && response.code.to_i != 200
        raise "Token request failed: #{result[:error]} (#{result[:error_description]})"
      end

      result
    end

    def auth_headers
      { 'Authorization' => "Bearer #{access_token}" }
    end

    def handle_response(response)
      if !response.success?
        # On error, response.body is a raw string (not parsed by UserAgent
        # even with json: true). Parse it to extract Graph's error message.
        error_body = begin
          response.body.is_a?(Hash) ? response.body : JSON.parse(response.body.to_s)
        rescue JSON::ParserError
          {}
        end
        error_msg = error_body.dig('error', 'message') || error_body['error_description'] || "HTTP #{response.code}"
        raise "Graph API error (#{response.code}): #{error_msg}"
      end

      response.data || response.body
    end
  end
end
