# KC: Add Setting for Teams directory sync — deactivate stale users toggle.
#
# Safety:
#   - Idempotent via create_if_not_exists
class AddKcTeamsDirectorySyncSettings < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Setting.create_if_not_exists(
      title:       'Teams Directory Sync — Deactivate Stale Users',
      name:        'kc_teams_directory_deactivate_stale',
      area:        'Kc::TeamsChat',
      description: 'When enabled, users with a microsoft_teams authorization who are no longer found in Azure AD will be deactivated during directory sync.',
      options:     {
        form: [
          {
            display:  'Deactivate stale users',
            null:     true,
            name:     'kc_teams_directory_deactivate_stale',
            tag:      'boolean',
            options:  {
              true  => 'yes',
              false => 'no',
            },
          },
        ],
      },
      state:        false,
      preferences:  {
        permission: ['admin'],
      },
      frontend:     true,
    )
  end

  def down
    Setting.find_by(name: 'kc_teams_directory_deactivate_stale')&.destroy
  end
end
