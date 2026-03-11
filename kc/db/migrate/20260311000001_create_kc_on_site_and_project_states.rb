# KC: Create "on-site" and "project" ticket states for tracking tickets
# that require on-site work or are part of a longer project.
#
# Uses the existing "open" state type so both states automatically
# integrate into Zammad's category system (open ticket counts, agent
# dropdowns, overviews) with zero upstream code modifications.
#
# Like "waiting for reply", these states auto-reset to "open" on
# customer reply via the ResetsWaitingForReplyState concern.
#
# Safety:
#   - Idempotent via create_if_not_exists
#   - Skipped on fresh installs (system_init_done guard)
class CreateKcOnSiteAndProjectStates < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    state_type = Ticket::StateType.find_by(name: 'open')
    return if state_type.nil?

    Ticket::State.create_if_not_exists(
      name:              'on-site',
      state_type_id:     state_type.id,
      ignore_escalation: true,
      active:            true,
      updated_by_id:     1,
      created_by_id:     1,
    )

    Ticket::State.create_if_not_exists(
      name:              'project',
      state_type_id:     state_type.id,
      ignore_escalation: true,
      active:            true,
      updated_by_id:     1,
      created_by_id:     1,
    )
  end

  def down
    return if !Setting.exists?(name: 'system_init_done')

    Ticket::State.find_by(name: 'on-site')&.destroy
    Ticket::State.find_by(name: 'project')&.destroy
  end
end
