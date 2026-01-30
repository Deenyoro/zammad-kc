# KC: Scheduler entry for backup polling of Teams chat messages every
# 15 minutes. Catches any messages missed by the webhook pathway
# (e.g. during subscription gaps or Graph outages).
#
# Safety:
#   - Idempotent via create_if_not_exists
class AddKcTeamsPollScheduler < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Scheduler.create_if_not_exists(
      name:          'Poll Microsoft Teams Chat messages.',
      method:        'Kc::PollTeamsChatMessagesJob.perform_now',
      period:        30.seconds,
      prio:          4,
      active:        true,
      updated_by_id: 1,
      created_by_id: 1,
      last_run:      Time.current,
    )
  end

  def down
    Scheduler.find_by(name: 'Poll Microsoft Teams Chat messages.')&.destroy
  end
end
