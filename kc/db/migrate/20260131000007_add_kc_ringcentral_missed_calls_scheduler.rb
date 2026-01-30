# KC: Scheduler entry for polling RingCentral call log for missed calls.
# Runs every 60 seconds. Only takes action when missed call settings are enabled.
#
# Safety:
#   - Idempotent via create_if_not_exists
class AddKcRingcentralMissedCallsScheduler < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Scheduler.create_if_not_exists(
      name:          'Poll RingCentral missed calls.',
      method:        'Kc::PollRingcentralMissedCallsJob.perform_now',
      period:        60.seconds,
      prio:          4,
      active:        true,
      updated_by_id: 1,
      created_by_id: 1,
      last_run:      Time.current,
    )
  end

  def down
    Scheduler.find_by(name: 'Poll RingCentral missed calls.')&.destroy
  end
end
