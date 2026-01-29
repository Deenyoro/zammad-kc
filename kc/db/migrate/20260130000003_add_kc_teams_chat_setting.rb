# KC: Add global Setting for Teams Chat thread window (hours).
# Controls how long after the last message in a conversation a new ticket
# should be created instead of appending to the existing one.
#
# Safety:
#   - Idempotent via create_if_not_exists
class AddKcTeamsChatSetting < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Setting.create_if_not_exists(
      title:       'Teams Chat Thread Window (hours)',
      name:        'kc_teams_chat_thread_window_hours',
      area:        'Kc::TeamsChat',
      description: 'Number of hours after the last message before a new ticket is created for the same Teams chat conversation. Set to 0 for a single ongoing ticket per chat.',
      options:     {
        form: [
          {
            display:  'Thread Window (hours)',
            null:     false,
            name:     'kc_teams_chat_thread_window_hours',
            tag:      'input',
            type:     'text',
          },
        ],
      },
      state:        24,
      preferences:  {
        permission: ['admin'],
      },
      frontend:     false,
    )
  end

  def down
    Setting.find_by(name: 'kc_teams_chat_thread_window_hours')&.destroy
  end
end
