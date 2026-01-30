# KC: ActiveRecord model for RingCentral webhook subscriptions.
#
# Each record tracks a single RingCentral subscription that watches
# the extension's message store for inbound SMS notifications.
#
# Safety:
#   - table_exists? guard so the app can boot before migration runs
#   - All associations and validations are inside the guard
class Kc::RingcentralSubscription < ApplicationModel
  self.table_name = 'kc_ringcentral_subscriptions'

  # Guard: skip associations, validations, and scopes if the table
  # doesn't exist yet (migration pending).
  if table_exists?
    belongs_to :channel

    validates :subscription_id, presence: true, uniqueness: true
    validates :client_state,    presence: true
    validates :expires_at,      presence: true

    # Subscriptions expiring within the given window (default 12 hours).
    scope :expiring_soon, ->(within: 12.hours) { where('expires_at <= ?', within.from_now) }

    # Subscriptions that have not yet expired.
    scope :active, -> { where('expires_at > ?', Time.current) }

    # Subscriptions belonging to active channels.
    scope :for_active_channels, -> { joins(:channel).where(channels: { active: true }) }
  end
rescue => e
  Rails.logger.warn "KC: RingcentralSubscription class body failed: #{e.message}"
end
