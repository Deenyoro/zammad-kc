# KC: Create kc_teams_subscriptions table for tracking Microsoft Graph
# webhook subscriptions per Teams chat.
#
# Each row represents one Graph subscription (change notification) that
# watches a specific Teams chat for new messages.
#
# Safety:
#   - Idempotent — guards with table_exists?
class CreateKcTeamsSubscriptions < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')
    return if table_exists?(:kc_teams_subscriptions)

    create_table :kc_teams_subscriptions do |t|
      t.references :channel,         null: false, foreign_key: true, type: :integer
      t.string     :chat_id,         null: false
      t.string     :subscription_id, null: false
      t.string     :client_state,    null: false
      t.datetime   :expires_at,      null: false

      t.timestamps limit: 3

      t.index :subscription_id, unique: true
      t.index [:channel_id, :chat_id]
      t.index :expires_at
    end
  end

  def down
    drop_table :kc_teams_subscriptions if table_exists?(:kc_teams_subscriptions)
  end
end
