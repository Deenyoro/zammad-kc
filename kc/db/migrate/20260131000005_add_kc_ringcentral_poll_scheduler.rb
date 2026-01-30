# KC: Scheduler entry for polling RingCentral message store every 60 seconds.
# Acts as a fallback for missed webhook notifications.
#
# Safety:
#   - Idempotent via create_if_not_exists
class AddKcRingcentralPollScheduler < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Scheduler.create_if_not_exists(
      name:          'Poll RingCentral SMS messages.',
      method:        'Kc::PollRingcentralSmsMessagesJob.perform_now',
      period:        60.seconds,
      prio:          4,
      active:        true,
      updated_by_id: 1,
      created_by_id: 1,
      last_run:      Time.current,
    )
  end

  def down
    Scheduler.find_by(name: 'Poll RingCentral SMS messages.')&.destroy
  end
end
