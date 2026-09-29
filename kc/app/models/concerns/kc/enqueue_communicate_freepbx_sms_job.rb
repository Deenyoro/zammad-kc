# KC: Concern prepended into Ticket::Article to enqueue outbound FreePBX
# text messages when an agent creates an article with type
# 'freepbx_sms_message'.
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
  module EnqueueCommunicateFreepbxSmsJob
    extend ActiveSupport::Concern

    prepended do
      after_create_commit :kc_enqueue_freepbx_sms_delivery
    rescue => e
      Rails.logger.warn "KC: EnqueueCommunicateFreepbxSmsJob prepended block failed: #{e.message}"
    end

    private

    def kc_enqueue_freepbx_sms_delivery
      return if Setting.get('import_mode')

      article_type = Ticket::Article::Type.find_by(id: type_id)
      return if article_type.nil? || article_type.name != 'freepbx_sms_message'

      sender = Ticket::Article::Sender.find_by(id: sender_id)
      return if sender.nil? || sender.name != 'Agent'

      # skip_send tickets: article created for routing/type purposes only
      return if preferences&.dig(:freepbx_sms, :skip_send)

      job_class = 'Kc::CommunicateFreepbxSmsJob'.safe_constantize
      if job_class.nil?
        Rails.logger.error 'KC: CommunicateFreepbxSmsJob class not found — cannot enqueue FreePBX SMS delivery'
        return
      end

      job_class.perform_later(id)
    rescue => e
      Rails.logger.error "KC: Failed to enqueue FreePBX SMS delivery for article #{id}: #{e.message}"
    end
  end
end
