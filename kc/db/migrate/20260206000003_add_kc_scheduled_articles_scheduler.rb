# KC: Scheduler entry for sending scheduled articles every 60 seconds.
#
# Safety:
#   - Idempotent via create_if_not_exists
class AddKcScheduledArticlesScheduler < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Scheduler.create_if_not_exists(
      name:          'Send KC scheduled articles.',
      method:        'Kc::SendScheduledArticlesJob.perform_now',
      period:        60.seconds,
      prio:          4,
      active:        true,
      updated_by_id: 1,
      created_by_id: 1,
      last_run:      Time.current,
    )
  end

  def down
    Scheduler.find_by(name: 'Send KC scheduled articles.')&.destroy
  end
end
