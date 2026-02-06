# KC: Create a "waiting for reply" ticket state for tracking tickets
# where the agent is waiting for a customer response.
#
# Uses the existing "open" state type so the new state automatically
# integrates into Zammad's category system (open ticket counts, agent
# dropdowns, overviews) with zero upstream code modifications.
#
# Safety:
#   - Idempotent via create_if_not_exists
#   - Skipped on fresh installs (system_init_done guard)
class CreateKcWaitingForReplyState < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    state_type = Ticket::StateType.find_by(name: 'open')
    return if state_type.nil?

    Ticket::State.create_if_not_exists(
      name:              'waiting for reply',
      state_type_id:     state_type.id,
      ignore_escalation: true,
      active:            true,
      updated_by_id:     1,
      created_by_id:     1,
    )
  end

  def down
    return if !Setting.exists?(name: 'system_init_done')

    Ticket::State.find_by(name: 'waiting for reply')&.destroy
  end
end
