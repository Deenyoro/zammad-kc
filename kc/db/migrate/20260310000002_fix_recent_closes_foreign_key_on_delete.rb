# KC: Add ON DELETE CASCADE to recent_closes.user_id FK.
# Upstream has `has_many :recent_closes, dependent: :delete_all` on User,
# but during user deletion a Taskbar after_destroy_commit callback can
# race and try to insert into recent_closes after the user row is gone,
# causing PG::ForeignKeyViolation. CASCADE at the DB level prevents this.
class FixRecentClosesForeignKeyOnDelete < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')
    return unless table_exists?(:recent_closes)

    # Check if FK exists before trying to remove it
    fk = foreign_keys(:recent_closes).find { |k| k.column == 'user_id' }
    remove_foreign_key :recent_closes, column: :user_id if fk
    add_foreign_key :recent_closes, :users, column: :user_id, on_delete: :cascade
  end

  def down
    return unless table_exists?(:recent_closes)

    fk = foreign_keys(:recent_closes).find { |k| k.column == 'user_id' }
    remove_foreign_key :recent_closes, column: :user_id if fk
    add_foreign_key :recent_closes, :users, column: :user_id
  end
end
