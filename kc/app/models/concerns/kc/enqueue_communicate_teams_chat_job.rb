# KC: Concern prepended into Ticket::Article to enqueue outbound Teams
# Chat messages when an agent creates an article with type 'teams_chat_message'.
#
# IMPORTANT: This module is *prepended* (not included) by kc_loader.rb,
# so we must use the `prepended` hook — not `included` — to register
# callbacks.  Using `included` with `prepend` would silently fail to
# register the after_create_commit callback.
#
# Safety:
#   - Checks article type and sender defensively
#   - Only fires on after_create_commit (not update)
#   - Wrapped in rescue to avoid breaking article creation on errors
#   - safe_constantize on job class to survive missing job file
module Kc
  module EnqueueCommunicateTeamsChatJob
    extend ActiveSupport::Concern

    prepended do
      after_create_commit :kc_enqueue_teams_chat_delivery
    rescue => e
      Rails.logger.warn "KC: EnqueueCommunicateTeamsChatJob prepended block failed: #{e.message}"
    end

    private

    def kc_enqueue_teams_chat_delivery
      return if Setting.get('import_mode')

      # Only for teams_chat_message type articles
      article_type = Ticket::Article::Type.find_by(id: type_id)
      return if article_type.nil? || article_type.name != 'teams_chat_message'

      # Only for agent-created articles (outbound)
      sender = Ticket::Article::Sender.find_by(id: sender_id)
      return if sender.nil? || sender.name != 'Agent'

      # safe_constantize guards against missing job class after upstream changes
      job_class = 'Kc::CommunicateTeamsChatJob'.safe_constantize
      if job_class.nil?
        Rails.logger.error 'KC: CommunicateTeamsChatJob class not found — cannot enqueue Teams Chat delivery'
        return
      end

      job_class.perform_later(id)
    rescue => e
      Rails.logger.error "KC: Failed to enqueue Teams Chat delivery for article #{id}: #{e.message}"
    end
  end
end
