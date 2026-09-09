# KC: Client for the KC PBX connector running on the FreePBX host.
#
# The connector exposes the PBX as data and control only — call detail
# records, extension state, and call origination. Every decision about
# tickets and text messages stays here in Zammad, so FreePBX and
# RingCentral are driven the same way from one place.
#
# RingCentral remains the system of record for SMS; this client never
# sends text messages. A FreePBX missed call results in a ticket here and
# an SMS sent through the RingCentral channel.
#
# Usage:
#   api = Kc::FreepbxApi.for_channel(channel)
#   api.calls(since_minutes: 60, missed: true, direction: 'inbound')
module Kc
  class FreepbxApi

    class Error < StandardError; end
    class AuthError < Error; end

    attr_reader :base_url, :token

    def initialize(base_url:, token:)
      @base_url = base_url.to_s.chomp('/')
      @token    = token.to_s
    end

    # Builds a client from a Freepbx::Account channel.
    def self.for_channel(channel)
      opts = channel.options.with_indifferent_access
      new(base_url: opts[:base_url], token: opts[:token])
    end

    def health
      get('/health', auth: false)
    end

    # Call detail records, oldest first.
    #
    # @param since [String] opaque watermark previously returned as `calldate`
    # @param since_minutes [Integer] relative window used when `since` is blank
    def calls(since: nil, since_minutes: nil, limit: 200, missed: false, direction: nil)
      params = { limit: limit }
      params[:since]         = since         if since.present?
      params[:since_minutes] = since_minutes if since.blank? && since_minutes.present?
      params[:missed]        = 1             if missed
      params[:direction]     = direction     if direction.present?
      result = get("/calls?#{params.to_query}")
      Array(result['calls'] || result[:calls])
    end

    def extensions
      result = get('/extensions')
      Array(result['extensions'] || result[:extensions])
    end

    # Click to call: rings the agent's extension, then dials the number.
    def originate(extension:, number:, caller_id: nil)
      body = { extension: extension, number: number }
      body[:caller_id] = caller_id if caller_id.present?
      post('/originate', body)
    end

    # Places an escalating alert call (primary number, then secondary).
    # `since` tells the connector how long the condition has been active so
    # it can apply the delay and quiet-hours policy.
    def alert(key:, message:, since:, policy: 'uptime', source: 'zammad')
      post('/alert', { key: key, message: message, since: since,
                       policy: policy, source: source })
    end

    def resolve_alert(key)
      post('/resolve', { key: key })
    end

    private

    def headers(auth: true)
      h = { 'Content-Type' => 'application/json' }
      h['Authorization'] = "Bearer #{token}" if auth
      h
    end

    def get(path, auth: true)
      raise Error, 'FreePBX base_url is not configured' if base_url.blank?

      response = UserAgent.get(
        "#{base_url}#{path}",
        {},
        {
          headers:       headers(auth: auth),
          open_timeout:  10,
          read_timeout:  30,
          total_timeout: 45,
          log:           { facility: 'kc_freepbx' },
          json:          true,
        },
      )
      handle(response)
    end

    def post(path, body)
      raise Error, 'FreePBX base_url is not configured' if base_url.blank?

      response = UserAgent.post(
        "#{base_url}#{path}",
        body,
        {
          headers:       headers,
          open_timeout:  10,
          read_timeout:  30,
          total_timeout: 45,
          log:           { facility: 'kc_freepbx' },
          json:          true,
        },
      )
      handle(response)
    end

    def handle(response)
      if !response.success?
        body = response.data.is_a?(Hash) ? response.data : {}
        message = body['error'] || body[:error] || "HTTP #{response.code}"
        raise AuthError, "FreePBX auth rejected: #{message}" if response.code.to_i == 401

        raise Error, "FreePBX API error (#{response.code}): #{message}"
      end

      response.data || {}
    end
  end
end
