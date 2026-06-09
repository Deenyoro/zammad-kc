# KC: Create kc_teams_sync_runs table for tracking Microsoft Teams directory
# sync runs (queued / running / completed / failed / canceled).
#
# delayed_job deletes a job row on completion, so finished jobs leave no trace
# and there is no native progress/cancel signal. This table gives the admin UI
# a durable record it can poll for live status, completed history, and a
# cooperative cancel flag the job honors between batches.
#
# Safety:
#   - Idempotent — guards with table_exists?
#   - Boots cleanly before the migration runs (model has table_exists? guard)
class CreateKcTeamsSyncRuns < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')
    return if table_exists?(:kc_teams_sync_runs)

    create_table :kc_teams_sync_runs do |t|
      t.references :channel,        null: false, foreign_key: { on_delete: :cascade }, type: :integer
      t.string     :status,         null: false, default: 'queued'
      t.integer    :delayed_job_id
      t.integer    :users_total,       null: false, default: 0
      t.integer    :users_processed,   null: false, default: 0
      t.integer    :users_created,     null: false, default: 0
      t.integer    :users_updated,     null: false, default: 0
      t.integer    :users_deactivated, null: false, default: 0
      t.boolean    :cancel_requested,  null: false, default: false
      t.text       :error
      t.datetime   :started_at,  limit: 3
      t.datetime   :finished_at, limit: 3
      t.integer    :created_by_id

      t.timestamps limit: 3

      t.index %i[channel_id created_at]
      t.index :status
    end
  end

  def down
    drop_table :kc_teams_sync_runs if table_exists?(:kc_teams_sync_runs)
  end
end
