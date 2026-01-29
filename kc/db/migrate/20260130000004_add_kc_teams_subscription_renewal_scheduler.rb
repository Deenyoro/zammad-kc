# KC: Scheduler entry to renew Microsoft Graph Teams chat subscriptions
# every 10 minutes. Graph subscriptions for chat resources expire after
# ~60 minutes, so this ensures timely renewal.
#
# Safety:
#   - Idempotent via create_if_not_exists
class AddKcTeamsSubscriptionRenewalScheduler < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Scheduler.create_if_not_exists(
      name:          'Renew Microsoft Teams Chat webhook subscriptions.',
      method:        'Kc::RenewTeamsSubscriptionsJob.perform_now',
      period:        10.minutes,
      prio:          3,
      active:        true,
      updated_by_id: 1,
      created_by_id: 1,
      last_run:      Time.current,
    )
  end

  def down
    Scheduler.find_by(name: 'Renew Microsoft Teams Chat webhook subscriptions.')&.destroy
  end
end
