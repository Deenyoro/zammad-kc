# KC: Create kc_ringcentral_subscriptions table for tracking RingCentral
# webhook subscriptions per channel.
#
# Each row represents one RingCentral subscription that watches for
# inbound SMS messages on the extension's message store.
#
# Safety:
#   - Idempotent — guards with table_exists?
class CreateKcRingcentralSubscriptions < ActiveRecord::Migration[7.0]
  def up
    return if table_exists?(:kc_ringcentral_subscriptions)

    create_table :kc_ringcentral_subscriptions do |t|
      t.references :channel,         null: false, foreign_key: true, type: :integer
      t.string     :subscription_id, null: false
      t.string     :client_state,    null: false
      t.datetime   :expires_at,      null: false

      t.timestamps limit: 3

      t.index :subscription_id, unique: true
      t.index :channel_id
      t.index :expires_at
    end
  end

  def down
    drop_table :kc_ringcentral_subscriptions if table_exists?(:kc_ringcentral_subscriptions)
  end
end
