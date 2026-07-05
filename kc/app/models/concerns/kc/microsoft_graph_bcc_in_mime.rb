# KC: Re-inject BCC header into raw MIME for Microsoft Graph API delivery.
#
# The Ruby Mail gem strips the Bcc header from encoded output per RFC 5322.
# For SMTP this is correct — BCC is handled via SMTP RCPT TO envelope
# commands. But Microsoft Graph API's sendMail endpoint with raw MIME needs
# the Bcc header present in the MIME to know who to deliver to.
#
# Without this fix, both system_bcc and article-level BCC are silently
# lost when sending email through Microsoft Graph API.
#
# This concern overrides MicrosoftGraph#send_message to re-inject the Bcc
# header into the MIME string before Base64 encoding and sending.
#
# NOTE: unlike most KC concerns this REPLACES the upstream method body rather
# than calling super (the Bcc must be injected into the MIME string *before*
# it is Base64-encoded, so there is no seam to wrap). That means an upstream
# change to send_message would be silently shadowed — the boot-time
# fingerprint check below detects exactly that and logs loudly so the copy
# can be re-synced.

module Kc
  module MicrosoftGraphBccInMime
    extend ActiveSupport::Concern

    # The upstream lines this concern's reimplementation mirrors. If any of
    # them disappears from lib/microsoft_graph.rb, upstream has rewritten
    # send_message and our copy is stale.
    UPSTREAM_FINGERPRINT = [
      'def send_message(mail)',
      'Base64.strict_encode64',
      'send_as_raw_body:',
      "make_request('sendMail'"
    ].freeze

    prepended do
      check_upstream_send_message_fingerprint
    end

    class_methods do
      def check_upstream_send_message_fingerprint
        upstream_file = Rails.root.join('lib/microsoft_graph.rb')
        return unless File.exist?(upstream_file)

        source = File.read(upstream_file)
        missing = UPSTREAM_FINGERPRINT.reject { |needle| source.include?(needle) }

        if missing.empty?
          Rails.logger.info 'KC: MicrosoftGraphBccInMime — upstream send_message unchanged, override is ACTIVE.'
        else
          Rails.logger.warn 'KC: MicrosoftGraphBccInMime — UPSTREAM send_message CHANGED ' \
                            "(missing: #{missing.join(' | ')}). The KC override shadows the new " \
                            'upstream body — re-sync kc/app/models/concerns/kc/microsoft_graph_bcc_in_mime.rb ' \
                            'with lib/microsoft_graph.rb#send_message.'
        end
      rescue => e
        Rails.logger.warn "KC: MicrosoftGraphBccInMime — failed to check upstream: #{e.message}"
      end
    end

    def send_message(mail)
      mime_string = mail.to_s

      # Re-inject BCC header that the Mail gem strips from encoded output.
      # mail.bcc still holds the addresses; only the MIME encoding omits them.
      if mail.bcc.present?
        bcc_value = Array(mail.bcc).join(', ')
        mime_string = "Bcc: #{bcc_value}\r\n#{mime_string}"
        Rails.logger.info "KC: MicrosoftGraphBccInMime — injected Bcc header: #{bcc_value}"
      else
        Rails.logger.info "KC: MicrosoftGraphBccInMime — no bcc on mail object"
      end

      headers = { 'Content-Type' => 'text/plain' }
      encoded = Base64.strict_encode64(mime_string)
      options = { headers:, send_as_raw_body: encoded }
      make_request('sendMail', method: :post, json: false, options:)
    end
  end
end
