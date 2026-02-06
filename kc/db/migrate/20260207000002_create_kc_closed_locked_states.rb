# KC: Create "closed (locked)" and "closed (locked until)" ticket states.
#
# "closed (locked)" — permanent lock. Uses the 'closed' state type.
#   Customer follow-ups create articles but never change the ticket state.
#
# "closed (locked until)" — timed lock. Uses 'pending action' state type
#   with next_state pointing to regular "closed". The built-in pending
#   scheduler (Ticket.process_pending) auto-transitions to "closed" when
#   pending_time expires. After that, normal reopen rules apply.
#
# Safety:
#   - Idempotent via create_if_not_exists
#   - Skipped on fresh installs (system_init_done guard)
class CreateKcClosedLockedStates < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    # --- closed (locked) ---
    closed_type = Ticket::StateType.find_by(name: 'closed')
    return if closed_type.nil?

    Ticket::State.create_if_not_exists(
      name:              'closed (locked)',
      state_type_id:     closed_type.id,
      ignore_escalation: true,
      active:            true,
      updated_by_id:     1,
      created_by_id:     1,
    )

    # --- closed (locked until) ---
    pending_action_type = Ticket::StateType.find_by(name: 'pending action')
    return if pending_action_type.nil?

    closed_state = Ticket::State.find_by(name: 'closed')
    return if closed_state.nil?

    Ticket::State.create_if_not_exists(
      name:              'closed (locked until)',
      state_type_id:     pending_action_type.id,
      next_state_id:     closed_state.id,
      ignore_escalation: true,
      active:            true,
      updated_by_id:     1,
      created_by_id:     1,
    )
  end

  def down
    return if !Setting.exists?(name: 'system_init_done')

    fallback_state = Ticket::State.find_by(name: 'closed')

    ['closed (locked until)', 'closed (locked)'].each do |name|
      state = Ticket::State.find_by(name: name)
      next if state.nil?

      if fallback_state
        Ticket.where(state_id: state.id).update_all(state_id: fallback_state.id)
      end
      state.destroy
    end
  end
end
