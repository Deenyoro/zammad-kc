# KC: ActiveRecord model for Microsoft Graph webhook subscriptions
# on Teams chat resources.
#
# Each record tracks a single Graph subscription that watches a specific
# Teams chat for new messages. Subscriptions expire after ~60 minutes
# and must be renewed proactively.
#
# Safety:
#   - table_exists? guard so the app can boot before migration runs
#   - All associations and validations are inside the guard
class Kc::TeamsSubscription < ApplicationModel
  self.table_name = 'kc_teams_subscriptions'

  # Guard: skip associations, validations, and scopes if the table
  # doesn't exist yet (migration pending).  This lets the app boot
  # cleanly even when the overlay is applied before migrations run.
  if table_exists?
    belongs_to :channel

    validates :chat_id,         presence: true
    validates :subscription_id, presence: true, uniqueness: true
    validates :client_state,    presence: true
    validates :expires_at,      presence: true

    # Subscriptions expiring within the given window (default 15 minutes).
    scope :expiring_soon, ->(within: 15.minutes) { where('expires_at <= ?', within.from_now) }

    # Subscriptions that have not yet expired.
    scope :active, -> { where('expires_at > ?', Time.current) }

    # Subscriptions belonging to active channels.
    scope :for_active_channels, -> { joins(:channel).where(channels: { active: true }) }
  end
rescue => e
  Rails.logger.warn "KC: TeamsSubscription class body failed: #{e.message}"
end
