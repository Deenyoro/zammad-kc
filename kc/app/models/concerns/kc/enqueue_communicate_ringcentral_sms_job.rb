# KC: Concern prepended into Ticket::Article to enqueue outbound RingCentral
# SMS messages when an agent creates an article with type 'ringcentral_sms_message'.
#
# IMPORTANT: This module is *prepended* (not included) by kc_loader.rb,
# so we must use the `prepended` hook — not `included` — to register
# callbacks.
#
# Safety:
#   - Checks article type and sender defensively
#   - Only fires on after_create_commit (not update)
#   - Wrapped in rescue to avoid breaking article creation on errors
#   - safe_constantize on job class to survive missing job file
module Kc
  module EnqueueCommunicateRingcentralSmsJob
    extend ActiveSupport::Concern

    prepended do
      after_create_commit :kc_enqueue_ringcentral_sms_delivery
    rescue => e
      Rails.logger.warn "KC: EnqueueCommunicateRingcentralSmsJob prepended block failed: #{e.message}"
    end

    private

    def kc_enqueue_ringcentral_sms_delivery
      return if Setting.get('import_mode')

      # Only for ringcentral_sms_message type articles
      article_type = Ticket::Article::Type.find_by(id: type_id)
      return if article_type.nil? || article_type.name != 'ringcentral_sms_message'

      # Only for agent-created articles (outbound)
      sender = Ticket::Article::Sender.find_by(id: sender_id)
      return if sender.nil? || sender.name != 'Agent'

      # Skip delivery when flagged (skip_send tickets — article created for
      # routing/type purposes only, no actual SMS should be sent)
      return if preferences&.dig(:ringcentral_sms, :skip_send)

      job_class = 'Kc::CommunicateRingcentralSmsJob'.safe_constantize
      if job_class.nil?
        Rails.logger.error 'KC: CommunicateRingcentralSmsJob class not found — cannot enqueue RingCentral SMS delivery'
        return
      end

      job_class.perform_later(id)
    rescue => e
      Rails.logger.error "KC: Failed to enqueue RingCentral SMS delivery for article #{id}: #{e.message}"
    end
  end
end
