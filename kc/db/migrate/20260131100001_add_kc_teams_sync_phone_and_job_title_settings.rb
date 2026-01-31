# KC: Add Settings for Teams directory sync — phone number and job title toggles.
#
# Safety:
#   - Idempotent via create_if_not_exists
class AddKcTeamsSyncPhoneAndJobTitleSettings < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Setting.create_if_not_exists(
      title:       'Teams Directory Sync — Sync Mobile Phone',
      name:        'kc_teams_directory_sync_phone',
      area:        'Kc::TeamsChat',
      description: 'Pull mobile numbers from Azure AD profiles. Falls back to MFA-registered phone numbers via the Authentication Methods API. Requires UserAuthenticationMethod.Read.All permission.',
      options:     {
        form: [
          {
            display:  'Sync mobile phone',
            null:     true,
            name:     'kc_teams_directory_sync_phone',
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

    Setting.create_if_not_exists(
      title:       'Teams Directory Sync — Sync Job Title',
      name:        'kc_teams_directory_sync_job_title',
      area:        'Kc::TeamsChat',
      description: 'Store Azure AD job titles in the user note field as [Teams Job Title: ...]. Updated on each sync without clobbering other note content.',
      options:     {
        form: [
          {
            display:  'Sync job title',
            null:     true,
            name:     'kc_teams_directory_sync_job_title',
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
    Setting.find_by(name: 'kc_teams_directory_sync_phone')&.destroy
    Setting.find_by(name: 'kc_teams_directory_sync_job_title')&.destroy
  end
end
