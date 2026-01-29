# KC: Renews expiring Microsoft Graph webhook subscriptions for all
# active Teams Chat channels.
#
# Called by the Scheduler every 10 minutes. Graph subscriptions for
# chat resources expire after ~60 minutes, so this job renews any
# subscription expiring within the next 15 minutes.
#
# On 404 (subscription deleted by Graph), recreates the subscription.
#
# Safety:
#   - safe_constantize on KC classes
#   - Per-channel rescue so one broken channel doesn't stop the others
class Kc::RenewTeamsSubscriptionsJob < ApplicationJob
  def perform
    manager_class = 'Kc::TeamsSubscriptionManager'.safe_constantize
    if manager_class.nil?
      Rails.logger.error 'KC Teams Renewal: TeamsSubscriptionManager class not found'
      return
    end

    Channel.where(area: 'MicrosoftTeamsChat::Account', active: true).find_each do |channel|
      manager_class.new(channel).renew_expiring_subscriptions
    rescue => e
      Rails.logger.error "KC Teams Renewal: Failed for channel #{channel.id}: #{e.message}"
    end
  end

  # Class method called by Scheduler (method: 'Kc::RenewTeamsSubscriptionsJob.perform_now')
  def self.perform_now
    new.perform
  end
end
