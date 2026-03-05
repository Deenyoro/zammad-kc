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
    OAUTH_SCOPES   = 'offline_access openid profile email Chat.Read Chat.ReadWrite Chat.Create ChatMessage.Send User.Read User.Read.All UserAuthenticationMethod.Read.All Files.Read.All Sites.Read.All'.freeze

    attr_reader :client_id, :client_secret, :tenant_id
    attr_accessor :access_token, :refresh_token

    def initialize(client_id:, client_secret:, tenant_id:, access_token: nil, refresh_token: nil)
      @client_id     = client_id
      @client_secret = client_secret
      @tenant_id     = tenant_id
      @access_token  = access_token
      @refresh_token = refresh_token
    end

    # Atomically reads tokens from a channel, refreshes if needed, persists,
    # and returns a ready-to-use client. Uses database-level locking to prevent
    # race conditions between concurrent threads (poll, send, webhook, health check).
    #
    # Microsoft Graph access tokens last ~1 hour. We skip refresh if the token
    # was refreshed within the last 50 minutes to avoid unnecessary rotation.
    #
    # @param channel [Channel] the Teams Chat channel
    # @param force_refresh [Boolean] force token refresh (e.g. for health checks)
    # @return [Kc::MicrosoftTeamsGraph] client with valid tokens
    def self.with_channel_tokens(channel, force_refresh: false)
      channel.with_lock do
        channel.reload
        opts = channel.options.with_indifferent_access

        graph = new(
          client_id:     opts[:client_id],
          client_secret: opts[:client_secret],
          tenant_id:     opts[:tenant_id],
          access_token:  opts[:access_token],
          refresh_token: opts[:refresh_token],
        )

        last_refresh = opts[:token_refreshed_at]
        last_refresh_time = begin
                              Time.zone.parse(last_refresh.to_s)
                            rescue ArgumentError, TypeError
                              Time.at(0)
                            end

        needs_refresh = force_refresh ||
                        last_refresh.blank? ||
                        last_refresh_time < 50.minutes.ago ||
                        opts[:access_token].blank?

        if needs_refresh
          graph.refresh_access_token!
          channel.options[:access_token]      = graph.access_token
          channel.options[:refresh_token]     = graph.refresh_token
          channel.options[:token_refreshed_at] = Time.current.utc.iso8601
          begin
            channel.save!
          rescue => e
            # Token already rotated server-side — old refresh token is dead.
            # Fall back to direct column update to avoid permanent token loss.
            Rails.logger.error "KC TeamsGraph: Token save failed (#{e.message}), attempting direct update for channel #{channel.id}"
            begin
              channel.update_columns(options: channel.options)
            rescue => e2
              Rails.logger.error "KC TeamsGraph: CRITICAL — Failed to persist refreshed tokens for channel #{channel.id}: #{e2.message}. Channel may need re-authentication."
            end
          end
        end

        graph
      end
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

    # Sends an image as a standalone chat message using hostedContents.
    # content_bytes must be raw binary image data (will be base64-encoded).
    # content_type should be the MIME type (e.g. 'image/png').
    # Returns the created message hash.
    def send_chat_image(chat_id, content_bytes, content_type:, filename: 'image')
      url = "#{GRAPH_BASE_URL}/chats/#{chat_id}/messages"
      encoded = Base64.strict_encode64(content_bytes)
      temporary_id = SecureRandom.hex(8)
      payload = {
        body: {
          contentType: 'html',
          content:     "<img src=\"../hostedContents/#{temporary_id}/$value\" alt=\"#{ERB::Util.html_escape(filename)}\">",
        },
        hostedContents: [
          {
            '@microsoft.graph.temporaryId': temporary_id,
            contentBytes:                   encoded,
            contentType:                    content_type,
          },
        ],
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

    # Downloads a hosted content blob (inline image) from a chat message.
    # Returns raw binary data.
    def get_hosted_content(chat_id, message_id, hosted_content_id)
      url = "#{GRAPH_BASE_URL}/chats/#{chat_id}/messages/#{message_id}/hostedContents/#{hosted_content_id}/$value"
      response = UserAgent.get(
        url,
        {},
        {
          headers:       auth_headers,
          open_timeout:  10,
          read_timeout:  30,
          total_timeout: 60,
          log:           { facility: 'kc_teams_graph' },
        },
      )
      raise "Graph API error (#{response.code}): Failed to download hosted content" unless response.success?

      response.body
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

    # Fetches authentication phone methods for a user (MFA-registered phones).
    # Requires UserAuthenticationMethod.Read.All permission.
    def get_user_phone_methods(user_id)
      graph_get("#{GRAPH_BASE_URL}/users/#{user_id}/authentication/phoneMethods")
    end

    # ------------------------------------------------------------------
    # Chats
    # ------------------------------------------------------------------

    # Lists the authenticated user's chats with full pagination.
    # Yields batches of chat objects to the given block, or returns the first page if no block given.
    #
    # @param top [Integer] page size (default 50)
    # @yield [Array<Hash>] batch of chat objects
    # @return [Hash, nil] first page result if no block given
    def list_chats(top: 50, &block)
      url = "#{GRAPH_BASE_URL}/me/chats?$top=#{top}&$expand=members"
      loop do
        result = graph_get(url)
        chats = result['value'] || []
        break if chats.empty?

        if block
          block.call(chats)
        else
          return result
        end

        url = result['@odata.nextLink']
        break if url.blank?
      end
    end

    # Gets a single chat by ID.
    def get_chat(chat_id)
      graph_get("#{GRAPH_BASE_URL}/chats/#{chat_id}?$expand=members")
    end

    # Creates or gets an existing 1:1 chat with a user.
    # The Graph API is idempotent — if a 1:1 chat already exists between
    # the authenticated user and the recipient, it returns the existing chat.
    #
    # @param recipient_user_id [String] Azure AD user ID of the recipient
    # @return [Hash] chat object including 'id'
    def create_chat(recipient_user_id)
      url = "#{GRAPH_BASE_URL}/chats"
      payload = {
        chatType: 'oneOnOne',
        members:  [
          {
            '@odata.type':    '#microsoft.graph.aadUserConversationMember',
            'roles':          ['owner'],
            'user@odata.bind': "#{GRAPH_BASE_URL}/users/#{me_user_id}",
          },
          {
            '@odata.type':    '#microsoft.graph.aadUserConversationMember',
            'roles':          ['owner'],
            'user@odata.bind': "#{GRAPH_BASE_URL}/users/#{recipient_user_id}",
          },
        ],
      }
      graph_post(url, payload)
    end

    # Searches tenant users by display name.
    #
    # @param query [String] search prefix for displayName
    # @param top [Integer] max results (default 10)
    # @return [Hash] Graph response with 'value' array of user objects
    def search_users(query, top: 10)
      sanitized = query.gsub("'", "''")
      encoded_query = ERB::Util.url_encode(sanitized)
      url = "#{GRAPH_BASE_URL}/users?$filter=startswith(displayName,'#{encoded_query}')&$top=#{top}&$select=id,displayName,mail,jobTitle"
      graph_get(url)
    end

    # Fetches all users from the tenant directory with pagination.
    # Yields batches of user objects to the given block, or returns the first page if no block given.
    #
    # @param top [Integer] page size (default 100, max 999)
    # @yield [Array<Hash>] batch of user objects
    # @return [Hash, nil] first page result if no block given
    def list_all_users(top: 100, &block)
      url = "#{GRAPH_BASE_URL}/users?$top=#{top}&$select=id,displayName,mail,jobTitle,department,userPrincipalName,accountEnabled,mobilePhone"
      loop do
        result = graph_get(url)
        users = result['value'] || []
        break if users.empty?

        if block
          block.call(users)
        else
          return result
        end

        url = result['@odata.nextLink']
        break if url.blank?
      end
    end

    private

    # Returns the authenticated user's ID, caching it for the lifetime of this instance.
    def me_user_id
      @me_user_id ||= me['id']
    end

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
        payload,
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

    def graph_patch(url, payload)
      response = UserAgent.patch(
        url,
        payload,
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
