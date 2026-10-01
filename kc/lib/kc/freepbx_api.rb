# KC: Client for the KC PBX connector running on the FreePBX host.
#
# The connector exposes the PBX as data and control only — call detail
# records, extension state, call origination, and (when the PBX has a
# texting provider: the Sangoma SMS module with SIPStation DIDs, or the
# open-source smsconnector module with Twilio, Telnyx, Bandwidth, VoIP.ms
# and friends) the text messages the PBX's SMS module holds. Every
# decision about tickets stays here in Zammad, so FreePBX and RingCentral
# are driven the same way from one place.
#
# Usage:
#   api = Kc::FreepbxApi.for_channel(channel)
#   api.calls(since_minutes: 60, missed: true, direction: 'inbound')
#   api.sms_messages(since: '2026-09-29T00:00:00Z', direction: 'inbound')
#
# SMS contract the connector implements (all JSON, bearer token auth):
#
#   GET  /sms/numbers
#        → { numbers: [{ number: "+14125550100", label: "Main", extension: "201" }] }
#        DIDs the PBX can text from. `label` and `extension` are optional.
#
#   GET  /sms?since=<ISO8601>&since_minutes=<n>&direction=inbound|outbound&limit=<n>
#        → { messages: [ <message>, ... ] }   oldest first
#        <message> = {
#          id:         "sms:12345",              stable per message
#          direction:  "inbound" | "outbound",
#          from:       "+14125550123",
#          to:         ["+14125550100"],          every recipient
#          text:       "hello",
#          created_at: "2026-09-29T14:02:11Z",
#          extension:  "201",                     optional, who sent an outbound text
#          media:      [{ id: "m1", url: "/sms/media/m1", content_type: "image/jpeg", filename: "photo.jpg" }]
#        }
#
#   GET  /sms/media/<id>   → the file bytes (used for `media[].url`, absolute
#        or relative to the connector base URL)
#
#   POST /sms/send  { from: "+1...", to: ["+1..."], text: "...",
#                     media: [{ filename:, content_type:, data_base64: }] }
#        → { id: "sms:12346" }
#
#   GET  /contacts   (optional)
#        → { contacts: [{ name: "Jane Smith", numbers: ["+14125550123"] }] }
#        The PBX phonebook, used to put names next to numbers on SMS tickets.
#
#   Webhook (optional, for instant delivery): the connector POSTs each new
#   message, in the <message> shape above (or { messages: [...] }), to
#   <zammad>/api/v1/kc/freepbx_sms_webhook with the header
#   `X-KC-Token: <this connection's token>`. Polling remains the backup.
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

    # The PBX phonebook (Contact Manager): [{ name:, numbers: ["+1..."] }].
    # Optional endpoint; older connectors answer 404.
    def contacts
      result = get('/contacts')
      Array(result['contacts'] || result[:contacts])
    end

    # ---- SMS -----------------------------------------------------------

    # Numbers the PBX can text from: [{ number:, label:, extension: }].
    def sms_numbers
      result = get('/sms/numbers')
      Array(result['numbers'] || result[:numbers])
    end

    # Text messages held by the PBX's SMS module, oldest first.
    def sms_messages(since: nil, since_minutes: nil, limit: 200, direction: nil)
      params = { limit: limit }
      params[:since]         = since         if since.present?
      params[:since_minutes] = since_minutes if since.blank? && since_minutes.present?
      params[:direction]     = direction     if direction.present?
      result = get("/sms?#{params.to_query}")
      Array(result['messages'] || result[:messages])
    end

    # Sends a text (and optional media) through the PBX. Returns the
    # connector's response, which carries the new message id.
    def sms_send(from:, to:, text:, media: [])
      body = { from: from, to: Array(to), text: text.to_s }
      body[:media] = media if media.present?
      post('/sms/send', body)
    end

    # Downloads one media item. `location` is the media entry's url, either
    # absolute or relative to the connector.
    def sms_media(location)
      raise Error, 'FreePBX base_url is not configured' if base_url.blank?

      url = location.to_s.match?(%r{\Ahttps?://}i) ? location.to_s : "#{base_url}/#{location.to_s.delete_prefix('/')}"
      response = UserAgent.get(
        url,
        {},
        {
          headers:       headers,
          open_timeout:  10,
          read_timeout:  60,
          total_timeout: 120,
          log:           { facility: 'kc_freepbx' },
        },
      )
      raise Error, "FreePBX media download error (#{response.code})" if !response.success?

      response.body
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
        body    = response.data.is_a?(Hash) ? response.data : {}
        message = body['error'] || body[:error]
        raise AuthError, "FreePBX auth rejected: #{message || "HTTP #{response.code}"}" if response.code.to_i == 401

        # Code 0 means the request never reached the connector — refused, timed
        # out, DNS. The transport error is the only thing that says which, and
        # it is what an alert ticket needs to be actionable.
        if response.code.to_i.zero?
          raise Error, "FreePBX connector unreachable at #{base_url}: #{transport_error(response)}"
        end

        raise Error, "FreePBX API error (#{response.code}): #{message || "HTTP #{response.code}"}"
      end

      response.data || {}
    end

    # UserAgent hands back the exception inspect string; the class and message
    # are the useful half of it.
    def transport_error(response)
      raw = response.respond_to?(:error) ? response.error.to_s : ''
      return 'no response' if raw.blank?

      raw[/\A#<([^:]+(?:::[^:]+)*):\s*(.+)>\z/m] ? "#{Regexp.last_match(1)}: #{Regexp.last_match(2)}" : raw
    end
  end
end
