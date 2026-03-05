# KC: Add agent_id to ticket_time_accountings for per-user time assignment.
# This column tracks which agent performed the work, distinct from
# created_by_id (which is always the logged-in user who recorded the entry).
#
# Safety:
#   - Idempotent — checks column_exists? before add/remove.
#   - Table guard — skips entirely if upstream renamed or removed the table.
#   - Backfill guard — only backfills if created_by_id column exists.
class AddAgentIdToTicketTimeAccountings < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    unless table_exists?(:ticket_time_accountings)
      say 'KC: ticket_time_accountings table not found — skipping (upstream renamed or removed?)'
      return
    end
    return if column_exists?(:ticket_time_accountings, :agent_id)

    add_reference :ticket_time_accountings, :agent, foreign_key: { to_table: :users }, null: true

    if column_exists?(:ticket_time_accountings, :created_by_id)
      Ticket::TimeAccounting.reset_column_information
      Ticket::TimeAccounting.in_batches.update_all('agent_id = created_by_id') # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def down
    unless table_exists?(:ticket_time_accountings)
      say 'KC: ticket_time_accountings table not found — skipping'
      return
    end
    return unless column_exists?(:ticket_time_accountings, :agent_id)

    remove_reference :ticket_time_accountings, :agent
  end
end
