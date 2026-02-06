# KC: Add Settings to suppress notifications for notes.
#
# Safety:
#   - Idempotent via create_if_not_exists
class AddKcSuppressInternalNoteNotificationsSetting < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Setting.create_if_not_exists(
      title:       'Suppress Internal Note Notifications',
      name:        'kc_suppress_internal_note_notifications',
      area:        'Kc::Extensions',
      description: 'When enabled, agent email and online notifications are suppressed for internal notes (including internal articles from Teams Chat messages).',
      options:     {
        form: [
          {
            display:  'Suppress internal note notifications',
            null:     true,
            name:     'kc_suppress_internal_note_notifications',
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
      title:       'Suppress All Note Notifications',
      name:        'kc_suppress_all_note_notifications',
      area:        'Kc::Extensions',
      description: 'When enabled, agent email and online notifications are suppressed for ALL notes (both internal and public). This is a superset of the internal-only setting.',
      options:     {
        form: [
          {
            display:  'Suppress all note notifications',
            null:     true,
            name:     'kc_suppress_all_note_notifications',
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
    Setting.find_by(name: 'kc_suppress_internal_note_notifications')&.destroy
    Setting.find_by(name: 'kc_suppress_all_note_notifications')&.destroy
  end
end
