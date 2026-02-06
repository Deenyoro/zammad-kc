# KC: Background job that sends scheduled articles when their time arrives.
#
# Called by Scheduler every 60 seconds. Finds all pending scheduled articles
# with scheduled_at <= now and executes each one, creating a real
# Ticket::Article that triggers the standard communication pipeline.
#
# Safety:
#   - Each record is processed independently — errors on one don't block others
#   - Pessimistic locking (SELECT FOR UPDATE SKIP LOCKED) inside a transaction
#     prevents double-send across concurrent workers
#   - UserInfo.with_user_id wraps execution for proper audit trail
#   - Failed records are marked with status 'failed' and error_message
#   - Status guard: only marks as 'failed' if still 'pending' (avoids
#     overwriting 'sent' after partial success)
class Kc::SendScheduledArticlesJob < ApplicationJob

  def perform
    model_class = 'Kc::ScheduledArticle'.safe_constantize
    if model_class.nil?
      Rails.logger.warn 'KC: SendScheduledArticlesJob — Kc::ScheduledArticle class not found'
      return
    end

    due_ids = model_class.due.pluck(:id)
    return if due_ids.empty?

    Rails.logger.info "KC: SendScheduledArticlesJob — processing #{due_ids.size} due article(s)"

    due_ids.each do |scheduled_id|
      process_one(model_class, scheduled_id)
    end
  end

  private

  def process_one(model_class, scheduled_id)
    # Wrap in a transaction so the FOR UPDATE lock is held for the entire
    # duration of execution, preventing double-send by concurrent workers.
    scheduled = nil
    model_class.transaction do
      scheduled = model_class.lock('FOR UPDATE SKIP LOCKED').find_by(id: scheduled_id, status: 'pending')
      return if scheduled.nil? # Already processed by another worker or status changed

      UserInfo.with_user_id(scheduled.created_by_id) do
        service = Kc::ExecuteScheduledArticle.new(scheduled)
        service.execute!
      end
    end
  rescue => e
    Rails.logger.error "KC: SendScheduledArticlesJob — failed to send scheduled article ##{scheduled_id} (ticket ##{scheduled&.ticket_id}): #{e.message}"
    # Only mark as failed if still pending — don't overwrite 'sent' after
    # partial success (e.g., article created but post-transaction cleanup failed).
    begin
      scheduled&.reload
      if scheduled&.status == 'pending'
        scheduled.update!(status: 'failed', error_message: e.message.truncate(500))
      end
    rescue => inner
      Rails.logger.error "KC: SendScheduledArticlesJob — failed to update status for ##{scheduled_id}: #{inner.message}"
    end
  end
end
