# KC: Renews expiring RingCentral webhook subscriptions for all
# active RingCentral SMS channels.
#
# Called by the Scheduler every 6 hours. RingCentral subscriptions
# can last up to 20 years, but we renew proactively.
#
# Safety:
#   - safe_constantize on KC classes
#   - Per-channel rescue so one broken channel doesn't stop the others
class Kc::RenewRingcentralSubscriptionsJob < ApplicationJob
  def perform
    manager_class = 'Kc::RingcentralSubscriptionManager'.safe_constantize
    if manager_class.nil?
      Rails.logger.error 'KC RingCentral Renewal: RingcentralSubscriptionManager class not found'
      return
    end

    Channel.where(area: 'RingCentralSms::Account', active: true).find_each do |channel|
      manager_class.new(channel).renew_expiring_subscriptions
    rescue => e
      Rails.logger.error "KC RingCentral Renewal: Failed for channel #{channel.id}: #{e.message}"
    end
  end

  # Class method called by Scheduler
  def self.perform_now
    new.perform
  end
end
