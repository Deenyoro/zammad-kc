# KC: Add bcc column to ticket_articles for BCC email recipients.
# Matches the spec of to/cc columns (string, limit: 3000, nullable).
#
# Safety:
#   - Idempotent — checks column_exists? before adding.
#   - Table guard — skips if upstream renamed or removed the table.
class AddKcBccToTicketArticles < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    unless table_exists?(:ticket_articles)
      say 'KC: ticket_articles table not found — skipping'
      return
    end
    return if column_exists?(:ticket_articles, :bcc)

    add_column :ticket_articles, :bcc, :string, limit: 3000, null: true
  end

  def down
    unless table_exists?(:ticket_articles)
      say 'KC: ticket_articles table not found — skipping'
      return
    end
    return unless column_exists?(:ticket_articles, :bcc)

    remove_column :ticket_articles, :bcc
  end
end
