# KC: ActiveRecord model for a single Microsoft Teams directory sync run.
#
# Each record tracks one execution of Kc::TeamsDirectorySyncJob — from the
# moment it is queued, through running (with incremental progress counters),
# to a terminal state (completed / failed / canceled). delayed_job deletes the
# job row on completion, so this is the only durable record of what happened.
#
# The admin "Sync Jobs" viewer polls these rows; cancel_requested is the
# cooperative flag the job checks between Graph paging batches.
#
# Safety:
#   - table_exists? guard so the app can boot before the migration runs
#   - All associations, validations, and scopes live inside the guard
class Kc::TeamsSyncRun < ApplicationModel
  self.table_name = 'kc_teams_sync_runs'

  STATUSES = %w[queued running completed failed canceled].freeze
  ACTIVE_STATUSES = %w[queued running].freeze

  if table_exists?
    belongs_to :channel, optional: true

    validates :status, inclusion: { in: STATUSES }

    # Most-recent runs first, optionally scoped to a channel.
    scope :recent, ->(limit = 25) { reorder(created_at: :desc).limit(limit) }

    # Runs that are still queued or running.
    scope :active, -> { where(status: ACTIVE_STATUSES) }

    # Active runs whose channel has been deleted or sync left dangling longer
    # than the cutoff — used to defensively reap stuck rows.
    scope :stale_active, ->(cutoff = 6.hours.ago) { active.where(updated_at: ...cutoff) }
  end

  def active?
    ACTIVE_STATUSES.include?(status)
  end

  def terminal?
    !active?
  end

  # Wall-clock duration in seconds, or nil if not finished/started.
  def duration_seconds
    return nil if started_at.blank?

    (finished_at || Time.current) - started_at
  end

  # Compact JSON-friendly representation for the admin viewer.
  def to_api_hash
    {
      id:                id,
      channel_id:        channel_id,
      status:            status,
      cancel_requested:  cancel_requested,
      users_total:       users_total,
      users_processed:   users_processed,
      users_created:     users_created,
      users_updated:     users_updated,
      users_deactivated: users_deactivated,
      error:             error,
      started_at:        started_at&.iso8601,
      finished_at:       finished_at&.iso8601,
      created_at:        created_at&.iso8601,
      duration_seconds:  duration_seconds&.round,
    }
  end
rescue => e
  Rails.logger.warn "KC: TeamsSyncRun class body failed: #{e.message}"
end
