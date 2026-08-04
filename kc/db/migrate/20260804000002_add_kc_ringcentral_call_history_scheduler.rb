# KC: Scheduler entry for polling RingCentral call log for call history.
# Runs every 5 minutes. Only takes action when the call history setting
# is enabled (kc_ringcentral_call_history_ticket).
#
# Safety:
#   - Idempotent via create_if_not_exists
class AddKcRingcentralCallHistoryScheduler < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Scheduler.create_if_not_exists(
      name:          'Poll RingCentral call history.',
      method:        'Kc::PollRingcentralCallHistoryJob.perform_now',
      period:        5.minutes,
      prio:          4,
      active:        true,
      updated_by_id: 1,
      created_by_id: 1,
      last_run:      Time.current,
    )
  end

  def down
    Scheduler.find_by(name: 'Poll RingCentral call history.')&.destroy
  end
end
