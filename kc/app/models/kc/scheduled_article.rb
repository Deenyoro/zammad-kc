# KC: ActiveRecord model for scheduled articles.
#
# Stores reply data that an agent wants to send at a future time.
# A background job polls for due records and creates real Ticket::Article
# records, which triggers the standard communication pipeline.
#
# article_data JSONB expected keys:
#   { body: string, type: string, sender: string, to: string?,
#     cc: string?, subject: string?, internal: bool?,
#     content_type: string?, form_id: integer?, preferences: hash? }
#
# ticket_attributes JSONB expected keys:
#   { state_id: integer?, priority_id: integer?, owner_id: integer?, ... }
#
# Safety:
#   - table_exists? guard so the app can boot before migration runs
#   - All associations and validations inside the guard
#   - Status validated against allowed values
#   - cancel! guards against non-pending status
class Kc::ScheduledArticle < ApplicationModel
  self.table_name = 'kc_scheduled_articles'

  VALID_STATUSES = %w[pending sent cancelled failed].freeze

  if table_exists?
    belongs_to :ticket
    belongs_to :created_by, class_name: 'User'
    belongs_to :updated_by, class_name: 'User'

    validates :ticket_id,      presence: true
    validates :article_data,   presence: true
    validates :scheduled_at,   presence: true
    validates :created_by_id,  presence: true
    validates :updated_by_id,  presence: true
    validates :status,         presence: true, inclusion: { in: VALID_STATUSES }

    scope :pending, -> { where(status: 'pending') }

    # Use CURRENT_TIMESTAMP in SQL to avoid stale Ruby Time.current
    scope :due,     -> { where(status: 'pending').where('scheduled_at <= CURRENT_TIMESTAMP') }

    # Cancel a scheduled article before it is sent.
    # Cleans up any cached attachments (form_id).
    # @param cancelled_by_id [Integer] the user who is cancelling (for audit trail)
    def cancel!(cancelled_by_id: nil)
      raise "Cannot cancel scheduled article ##{id} with status '#{status}'" unless status == 'pending'

      by_id = cancelled_by_id || UserInfo.current_user_id || updated_by_id
      update!(status: 'cancelled', updated_by_id: by_id)

      # Best-effort cleanup — don't fail cancellation if cache is already gone
      form_id = article_data&.dig('form_id')
      if form_id.present? && form_id.to_s.match?(/\A\d+\z/) && defined?(UploadCache)
        UploadCache.new(form_id.to_i).destroy
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "KC: Failed to cancel scheduled article #{id}: #{e.message}"
      raise
    rescue RuntimeError
      # Re-raise status guard errors
      raise
    rescue => e
      # Log but don't re-raise for UploadCache cleanup failures —
      # the status update already succeeded if we got past update!
      Rails.logger.warn "KC: UploadCache cleanup failed for scheduled article #{id}: #{e.message}"
    end
  end
rescue => e
  Rails.logger.warn "KC: ScheduledArticle class body failed: #{e.message}"
end
