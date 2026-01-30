# KC: Scheduler entry to renew RingCentral webhook subscriptions
# every 6 hours. RingCentral subscriptions can last up to 20 years,
# but we renew proactively to ensure they stay active.
#
# Safety:
#   - Idempotent via create_if_not_exists
class AddKcRingcentralSubscriptionRenewalScheduler < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Scheduler.create_if_not_exists(
      name:          'Renew RingCentral SMS webhook subscriptions.',
      method:        'Kc::RenewRingcentralSubscriptionsJob.perform_now',
      period:        6.hours,
      prio:          3,
      active:        true,
      updated_by_id: 1,
      created_by_id: 1,
      last_run:      Time.current,
    )
  end

  def down
    Scheduler.find_by(name: 'Renew RingCentral SMS webhook subscriptions.')&.destroy
  end
end
