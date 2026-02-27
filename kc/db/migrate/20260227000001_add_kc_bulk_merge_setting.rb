# KC: Add setting to enable bulk-merge from ticket overviews.
#
# When enabled, agents can select multiple tickets in the overview and merge
# them into a parent ticket via the bulk action bar.
#
# Safety:
#   - Idempotent via create_if_not_exists
class AddKcBulkMergeSetting < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Setting.create_if_not_exists(
      title:       'KC: Bulk Merge',
      name:        'kc_bulk_merge',
      area:        'Kc::General',
      description: 'Allow agents to bulk-merge tickets from the overview. Selected tickets are merged into a parent ticket, then set to closed (not merged) so they remain visible in overviews.',
      options:     {
        form: [
          {
            display:  'Bulk merge',
            null:     true,
            name:     'kc_bulk_merge',
            tag:      'boolean',
            options:  {
              true  => 'yes',
              false => 'no',
            },
          },
        ],
      },
      state:        true,
      preferences:  {
        permission: ['admin'],
      },
      frontend:     true,
    )
  end

  def down
    Setting.find_by(name: 'kc_bulk_merge')&.destroy
  end
end
