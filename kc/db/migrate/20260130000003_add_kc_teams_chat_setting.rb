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
      frontend:     true,
    )

    Setting.create_if_not_exists(
      title:       'Teams Chat Active Lookback (hours)',
      name:        'kc_teams_chat_active_lookback_hours',
      area:        'Kc::TeamsChat',
      description: 'How many hours back to consider a ticket "active" for priority polling. Active chats are polled every scheduler run (~1 min).',
      options:     {
        form: [
          {
            display:  'Active Lookback (hours)',
            null:     false,
            name:     'kc_teams_chat_active_lookback_hours',
            tag:      'input',
            type:     'text',
          },
        ],
      },
      state:        2,
      preferences:  {
        permission: ['admin'],
      },
      frontend:     true,
    )

    Setting.create_if_not_exists(
      title:       'Teams Chat Discovery Interval (minutes)',
      name:        'kc_teams_chat_discovery_interval_minutes',
      area:        'Kc::TeamsChat',
      description: 'How often (in minutes) to do a full scan of all Teams chats. New conversations are found during discovery.',
      options:     {
        form: [
          {
            display:  'Discovery Interval (minutes)',
            null:     false,
            name:     'kc_teams_chat_discovery_interval_minutes',
            tag:      'input',
            type:     'text',
          },
        ],
      },
      state:        5,
      preferences:  {
        permission: ['admin'],
      },
      frontend:     true,
    )
  end

  def down
    Setting.find_by(name: 'kc_teams_chat_thread_window_hours')&.destroy
    Setting.find_by(name: 'kc_teams_chat_active_lookback_hours')&.destroy
    Setting.find_by(name: 'kc_teams_chat_discovery_interval_minutes')&.destroy
  end
end
