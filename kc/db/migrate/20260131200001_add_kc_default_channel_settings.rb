# KC: Add default channel ID settings for SMS and Teams new conversation pages.
#
# These settings let admins pre-select which channel/account is used as the
# "From" number/account when agents create new SMS or Teams conversations.
#
# Safety:
#   - Idempotent via create_if_not_exists
class AddKcDefaultChannelSettings < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Setting.create_if_not_exists(
      title:       'RingCentral SMS Default From Channel',
      name:        'kc_ringcentral_sms_default_channel_id',
      area:        'Kc::RingCentralSms',
      description: 'Default RingCentral SMS channel ID used as the "From" number on new SMS conversations. Empty means use the first active channel.',
      options:     {
        form: [
          {
            display:  'Default From Channel ID',
            null:     true,
            name:     'kc_ringcentral_sms_default_channel_id',
            tag:      'input',
            type:     'text',
          },
        ],
      },
      state:        '',
      preferences:  {
        permission: ['admin'],
      },
      frontend:     false,
    )

    Setting.create_if_not_exists(
      title:       'Teams Chat Default From Channel',
      name:        'kc_teams_default_channel_id',
      area:        'Kc::TeamsChat',
      description: 'Default Microsoft Teams channel ID used as the "From" account on new Teams conversations. Empty means use the first active channel.',
      options:     {
        form: [
          {
            display:  'Default From Channel ID',
            null:     true,
            name:     'kc_teams_default_channel_id',
            tag:      'input',
            type:     'text',
          },
        ],
      },
      state:        '',
      preferences:  {
        permission: ['admin'],
      },
      frontend:     false,
    )
  end

  def down
    Setting.find_by(name: 'kc_ringcentral_sms_default_channel_id')&.destroy
    Setting.find_by(name: 'kc_teams_default_channel_id')&.destroy
  end
end
