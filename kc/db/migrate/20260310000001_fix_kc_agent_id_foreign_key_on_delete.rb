# KC: Change the agent_id FK on ticket_time_accountings to SET NULL on delete.
# Without this, deleting a user who has time accounting entries fails with
# PG::ForeignKeyViolation because Zammad's User model doesn't know about
# our custom agent_id column.
class FixKcAgentIdForeignKeyOnDelete < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')
    return unless table_exists?(:ticket_time_accountings)
    return unless column_exists?(:ticket_time_accountings, :agent_id)

    fk = foreign_keys(:ticket_time_accountings).find { |k| k.column == 'agent_id' }
    remove_foreign_key :ticket_time_accountings, column: :agent_id if fk
    add_foreign_key :ticket_time_accountings, :users, column: :agent_id, on_delete: :nullify
  end

  def down
    return unless table_exists?(:ticket_time_accountings)
    return unless column_exists?(:ticket_time_accountings, :agent_id)

    fk = foreign_keys(:ticket_time_accountings).find { |k| k.column == 'agent_id' }
    remove_foreign_key :ticket_time_accountings, column: :agent_id if fk
    add_foreign_key :ticket_time_accountings, :users, column: :agent_id
  end
end
