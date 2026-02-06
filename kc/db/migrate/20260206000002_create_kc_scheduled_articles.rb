# KC: Create kc_scheduled_articles table for storing replies that agents
# schedule to be sent at a future time.
#
# The scheduled article data is stored as JSONB. When the scheduled time
# arrives, a background job creates a real Ticket::Article from the stored
# data, which triggers the standard email communication pipeline.
#
# Safety:
#   - Skipped on fresh installs (system_init_done guard)
class CreateKcScheduledArticles < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    create_table :kc_scheduled_articles do |t|
      t.bigint   :ticket_id,        null: false
      t.jsonb    :article_data,      null: false, default: {}
      t.jsonb    :ticket_attributes, default: {}
      t.datetime :scheduled_at,      null: false
      t.string   :status,            null: false, default: 'pending'
      t.text     :error_message
      t.bigint   :created_by_id,     null: false
      t.bigint   :updated_by_id,     null: false
      t.timestamps
    end

    add_index :kc_scheduled_articles, :ticket_id
    add_index :kc_scheduled_articles, :scheduled_at
    # Composite index covers both the job's due query (status + scheduled_at)
    # and any status-only lookups — single-column status index is redundant.
    add_index :kc_scheduled_articles, %i[status scheduled_at], name: 'index_kc_scheduled_articles_on_status_and_scheduled_at'
  end

  def down
    drop_table :kc_scheduled_articles if table_exists?(:kc_scheduled_articles)
  end
end
