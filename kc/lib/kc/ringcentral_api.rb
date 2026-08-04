# KC: RingCentral REST API client for SMS/MMS integration.
#
# Wraps the RingCentral Connect Platform API for:
#   - OAuth2 token exchange and refresh (Basic auth header)
#   - Send SMS (JSON) and MMS (multipart/form-data)
#   - Message store queries (inbox polling)
#   - Webhook subscription management (create, renew, delete)
#   - Extension info and phone number lookup
#   - Phone number normalization (E.164) and conversation key generation
#
# Uses Zammad's built-in UserAgent for HTTP (no extra gems).
# MMS uploads use Net::HTTP directly (UserAgent doesn't support multipart).
#
# Usage:
#   rc = Kc::RingcentralApi.new(
#     client_id:     '...',
#     client_secret: '...',
#     access_token:  '...',
#     refresh_token: '...',
#   )
#   rc.send_sms(from: '+14125567007', to: '+15551234567', text: 'Hello!')
#
module Kc
  class RingcentralApi
    API_BASE_URL   = 'https://platform.ringcentral.com'.freeze
    OAUTH_BASE_URL = 'https://platform.ringcentral.com/restapi/oauth'.freeze

    attr_reader :client_id, :client_secret
    attr_accessor :access_token, :refresh_token

    def initialize(client_id:, client_secret:, access_token: nil, refresh_token: nil)
      @client_id     = client_id
      @client_secret = client_secret
      @access_token  = access_token
      @refresh_token = refresh_token
    end

    # Atomically reads tokens from a channel, refreshes if needed, persists,
    # and returns a ready-to-use client. Uses database-level locking to prevent
    # race conditions between concurrent threads (poll, send, health check).
    #
    # RingCentral access tokens last 1 hour. We skip refresh if the token
    # was refreshed within the last 50 minutes to avoid unnecessary rotation
    # of the refresh token (which RingCentral invalidates on each use).
    #
    # @param channel [Channel] the RingCentral SMS channel
    # @param force_refresh [Boolean] force token refresh (e.g. for health checks)
    # @return [Kc::RingcentralApi] client with valid tokens
    def self.with_channel_tokens(channel, force_refresh: false)
      channel.with_lock do
        channel.reload
        opts = channel.options.with_indifferent_access

        rc = new(
          client_id:     opts[:client_id],
          client_secret: opts[:client_secret],
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
          rc.refresh_access_token!
          channel.options[:access_token]      = rc.access_token
          channel.options[:refresh_token]     = rc.refresh_token
          channel.options[:token_refreshed_at] = Time.current.utc.iso8601
          begin
            channel.save!
          rescue => e
            # Token already rotated server-side — old refresh token is dead.
            # Fall back to direct column update to avoid permanent token loss.
            Rails.logger.error "KC RingCentral: Token save failed (#{e.message}), attempting direct update for channel #{channel.id}"
            begin
              channel.update_columns(options: channel.options)
            rescue => e2
              Rails.logger.error "KC RingCentral: CRITICAL — Failed to persist refreshed tokens for channel #{channel.id}: #{e2.message}. Channel may need re-authentication."
            end
          end
        end

        rc
      end
    end

    # ------------------------------------------------------------------
    # OAuth2 helpers
    # ------------------------------------------------------------------

    # Returns the URL to redirect the user to for OAuth consent.
    def authorize_url(redirect_uri, state)
      params = {
        response_type: 'code',
        client_id:     client_id,
        redirect_uri:  redirect_uri,
        state:         state,
      }
      "#{API_BASE_URL}/restapi/oauth/authorize?#{params.to_query}"
    end

    # Exchanges an authorization code for access + refresh tokens.
    # RingCentral requires Basic auth header (not body params like Microsoft).
    def exchange_code(code, redirect_uri)
      url  = "#{OAUTH_BASE_URL}/token"
      body = {
        grant_type:   'authorization_code',
        code:         code,
        redirect_uri: redirect_uri,
      }
      response = post_form_with_basic_auth(url, body)
      raise "Token exchange failed: #{response[:error_description] || response[:error]}" if response[:access_token].blank?

      self.access_token  = response[:access_token]
      self.refresh_token = response[:refresh_token]
      response
    end

    # Refreshes the access token using the stored refresh token.
    # RingCentral rotates refresh tokens on each use — always persist the new one.
    def refresh_access_token!
      raise 'No refresh token available' if refresh_token.blank?

      url  = "#{OAUTH_BASE_URL}/token"
      body = {
        grant_type:    'refresh_token',
        refresh_token: refresh_token,
      }
      response = post_form_with_basic_auth(url, body)
      raise "Token refresh failed: #{response[:error_description] || response[:error]}" if response[:access_token].blank?

      self.access_token  = response[:access_token]
      # RingCentral always returns a new refresh token — must persist it.
      self.refresh_token = response[:refresh_token] if response[:refresh_token].present?
      response
    end

    # ------------------------------------------------------------------
    # SMS
    # ------------------------------------------------------------------

    # Sends an SMS message (text only, no attachments).
    # Returns the created message hash.
    def send_sms(from:, to:, text:)
      url = "#{API_BASE_URL}/restapi/v1.0/account/~/extension/~/sms"
      payload = {
        from: { phoneNumber: from },
        to:   Array(to).map { |num| { phoneNumber: num } },
        text: text,
      }
      api_post(url, payload)
    end

    # ------------------------------------------------------------------
    # MMS (multipart/form-data via Net::HTTP)
    # ------------------------------------------------------------------

    # Sends an MMS message with attachments.
    # attachments: Array of { filename:, content_type:, data: } hashes
    # Limits: 1.5MB combined, 10 files max.
    def send_mms(from:, to:, text:, attachments:)
      url = "#{API_BASE_URL}/restapi/v1.0/account/~/extension/~/mms"
      uri = URI.parse(url)

      boundary = "ZammadKC#{SecureRandom.hex(16)}"

      # Build multipart body
      body_parts = []

      # JSON metadata part
      json_part = {
        from: { phoneNumber: from },
        to:   Array(to).map { |num| { phoneNumber: num } },
        text: text.to_s,
      }
      body_parts << "--#{boundary}\r\n"
      body_parts << "Content-Type: application/json\r\n"
      body_parts << "Content-Disposition: form-data; name=\"json\"\r\n\r\n"
      body_parts << json_part.to_json
      body_parts << "\r\n"

      # Attachment parts
      Array(attachments).first(10).each_with_index do |att, idx|
        # Sanitize filename: strip quotes, newlines, and non-ASCII to prevent
        # header injection in the multipart Content-Disposition.
        safe_filename = (att[:filename] || "attachment_#{idx}").to_s
                          .gsub(/["\\]/, '_')
                          .gsub(/[\r\n]/, '')
                          .encode('ASCII', invalid: :replace, undef: :replace, replace: '_')
                          .truncate(200, omission: '')
        safe_content_type = (att[:content_type] || 'application/octet-stream').to_s
                              .gsub(/[\r\n]/, '')
        body_parts << "--#{boundary}\r\n"
        body_parts << "Content-Type: #{safe_content_type}\r\n"
        body_parts << "Content-Disposition: form-data; name=\"attachment#{idx}\"; filename=\"#{safe_filename}\"\r\n\r\n"
        body_parts << att[:data]
        body_parts << "\r\n"
      end

      body_parts << "--#{boundary}--\r\n"
      body_str = body_parts.join

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl     = true
      http.open_timeout = 10
      http.read_timeout = 60

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Authorization'] = "Bearer #{access_token}"
      request['Content-Type']  = "multipart/form-data; boundary=#{boundary}"
      request.body = body_str

      response = http.request(request)

      if response.code.to_i >= 400
        error_body = begin
          JSON.parse(response.body)
        rescue JSON::ParserError
          {}
        end
        error_msg = error_body.dig('message') || error_body.dig('errorCode') || "HTTP #{response.code}"
        raise "RingCentral MMS error (#{response.code}): #{error_msg}"
      end

      JSON.parse(response.body).with_indifferent_access
    end

    # ------------------------------------------------------------------
    # Message Store (for polling)
    # ------------------------------------------------------------------

    # Fetches messages from the message store.
    # Options: message_type ('SMS'), direction ('Inbound'/'Outbound'),
    #          date_from (ISO 8601), per_page (default 100)
    def get_message_store(message_type: 'SMS', direction: nil, date_from: nil, per_page: 100)
      url = "#{API_BASE_URL}/restapi/v1.0/account/~/extension/~/message-store"
      params = { messageType: message_type, perPage: per_page }
      params[:direction]   = direction if direction.present?
      params[:dateFrom]    = date_from if date_from.present?
      params[:availability] = 'Alive'

      query = params.to_query
      api_get("#{url}?#{query}")
    end

    # Downloads an attachment from a message.
    # Returns the raw binary data.
    def get_message_attachment(message_id, attachment_id)
      url = "#{API_BASE_URL}/restapi/v1.0/account/~/extension/~/message-store/#{message_id}/content/#{attachment_id}"

      response = UserAgent.get(
        url,
        {},
        {
          headers:       auth_headers,
          open_timeout:  10,
          read_timeout:  60,
          total_timeout: 120,
          log:           { facility: 'kc_ringcentral_api' },
        },
      )

      if !response.success?
        raise "RingCentral attachment download error (#{response.code})"
      end

      response.body
    end

    # ------------------------------------------------------------------
    # Webhook Subscriptions
    # ------------------------------------------------------------------

    # Creates a webhook subscription for instant SMS notifications.
    # event_filters: Array of resource paths to watch.
    # Returns the subscription hash (including id, expirationTime).
    def create_subscription(notification_url, event_filters, expires_in: nil, verification_token: nil)
      url = "#{API_BASE_URL}/restapi/v1.0/subscription"

      delivery_mode = {
        transportType: 'WebHook',
        address:       notification_url,
      }
      # verificationToken is sent back by RingCentral as a Verification-Token
      # HTTP header with every webhook notification, allowing us to authenticate
      # that notifications genuinely originate from RingCentral.
      delivery_mode[:verificationToken] = verification_token if verification_token.present?

      payload = {
        eventFilters: Array(event_filters),
        deliveryMode: delivery_mode,
        expiresIn:    expires_in,
      }.compact

      api_post(url, payload)
    end

    # Renews (extends) an existing subscription.
    def renew_subscription(subscription_id)
      url = "#{API_BASE_URL}/restapi/v1.0/subscription/#{subscription_id}/renew"
      api_post(url, {})
    end

    # Deletes a subscription.
    def delete_subscription(subscription_id)
      url = "#{API_BASE_URL}/restapi/v1.0/subscription/#{subscription_id}"
      api_delete(url)
    end

    # ------------------------------------------------------------------
    # Extension Info
    # ------------------------------------------------------------------

    # Fetches the authenticated extension's profile.
    def extension_info
      api_get("#{API_BASE_URL}/restapi/v1.0/account/~/extension/~")
    end

    # Fetches SMS-capable phone numbers for the extension.
    def phone_numbers
      api_get("#{API_BASE_URL}/restapi/v1.0/account/~/extension/~/phone-number")
    end

    # ------------------------------------------------------------------
    # Call Log (for missed call detection)
    # ------------------------------------------------------------------

    # Fetches call log entries from the RingCentral API.
    # Options: direction ('Inbound'), result ('Missed'), date_from (ISO 8601),
    #          per_page (default 100), type ('Voice'), page (1-based)
    # NOTE: records are returned newest-first; use the page parameter to
    # paginate — advancing dateFrom past the newest record does NOT work.
    def get_call_log(direction: nil, result: nil, date_from: nil, per_page: 100, type: nil, page: nil)
      url = "#{API_BASE_URL}/restapi/v1.0/account/~/extension/~/call-log"
      params = { perPage: per_page, view: 'Simple' }
      params[:direction] = direction if direction.present?
      params[:result]    = result    if result.present?
      params[:dateFrom]  = date_from if date_from.present?
      params[:type]      = type      if type.present?
      params[:page]      = page      if page.present?

      query = params.to_query
      api_get("#{url}?#{query}")
    end

    # ------------------------------------------------------------------
    # Phone normalization helpers
    # ------------------------------------------------------------------

    # Normalizes a phone number to E.164 format.
    # Strips non-digit chars, prepends +1 if 10 digits (US).
    def self.normalize_phone(number)
      return nil if number.blank?

      digits = number.to_s.gsub(/[^\d+]/, '')
      digits = digits.delete('+')

      case digits.length
      when 10
        "+1#{digits}"   # US number without country code
      when 11
        "+#{digits}"    # Already has country code
      else
        "+#{digits}"    # International — best effort
      end
    end

    # Generates a deterministic conversation key from a set of phone numbers.
    # Sorted E.164 numbers joined by ':' — consistent regardless of who sent.
    def self.conversation_key(*numbers)
      numbers.flatten.map { |n| normalize_phone(n) }.compact.sort.join(':')
    end

    private

    # ------------------------------------------------------------------
    # HTTP helpers using Zammad's UserAgent
    # ------------------------------------------------------------------

    def api_get(url)
      response = UserAgent.get(
        url,
        {},
        {
          headers:       auth_headers,
          json:          true,
          open_timeout:  10,
          read_timeout:  30,
          total_timeout: 60,
          log:           { facility: 'kc_ringcentral_api' },
        },
      )
      handle_response(response)
    end

    def api_post(url, payload)
      response = UserAgent.post(
        url,
        payload,
        {
          headers:       auth_headers,
          json:          true,
          open_timeout:  10,
          read_timeout:  30,
          total_timeout: 60,
          log:           { facility: 'kc_ringcentral_api' },
        },
      )
      handle_response(response)
    end

    def api_delete(url)
      response = UserAgent.delete(
        url,
        {},
        {
          headers:       auth_headers,
          json:          true,
          open_timeout:  10,
          read_timeout:  30,
          total_timeout: 60,
          log:           { facility: 'kc_ringcentral_api' },
        },
      )
      # DELETE returns 204 No Content on success
      return true if response.code.to_i == 204

      handle_response(response)
    end

    # Posts form-encoded data with Basic auth header (for OAuth token endpoints).
    # RingCentral requires Authorization: Basic base64(client_id:client_secret).
    def post_form_with_basic_auth(url, body)
      credentials = Base64.strict_encode64("#{client_id}:#{client_secret}")

      response = UserAgent.post(
        url,
        body,
        {
          headers: {
            'Authorization' => "Basic #{credentials}",
          },
          open_timeout:  10,
          read_timeout:  30,
          total_timeout: 60,
          log:           { facility: 'kc_ringcentral_api' },
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
        error_body = begin
          response.body.is_a?(Hash) ? response.body : JSON.parse(response.body.to_s)
        rescue JSON::ParserError
          {}
        end
        error_msg = error_body.dig('message') || error_body.dig('errorCode') || error_body.dig('error', 'message') || "HTTP #{response.code}"
        raise "RingCentral API error (#{response.code}): #{error_msg}"
      end

      response.data || response.body
    end
  end
end
