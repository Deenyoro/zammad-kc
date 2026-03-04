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

module Kc
  module MicrosoftGraphBccInMime
    extend ActiveSupport::Concern

    def send_message(mail)
      mime_string = mail.to_s

      # Re-inject BCC header that the Mail gem strips from encoded output.
      # mail.bcc still holds the addresses; only the MIME encoding omits them.
      if mail.bcc.present?
        bcc_value = Array(mail.bcc).join(', ')
        mime_string = "Bcc: #{bcc_value}\r\n#{mime_string}"
      end

      headers = { 'Content-Type' => 'text/plain' }
      encoded = Base64.strict_encode64(mime_string)
      options = { headers:, send_as_raw_body: encoded }
      make_request('sendMail', method: :post, json: false, options:)
    end
  end
end
