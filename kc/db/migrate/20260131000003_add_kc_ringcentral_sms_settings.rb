# KC: Add global Settings for RingCentral SMS integration.
#
# Safety:
#   - Idempotent via create_if_not_exists
class AddKcRingcentralSmsSettings < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Setting.create_if_not_exists(
      title:       'RingCentral SMS Thread Window (hours)',
      name:        'kc_ringcentral_sms_thread_window_hours',
      area:        'Kc::RingCentralSms',
      description: 'Number of hours after the last message before a new ticket is created for the same phone number pair. Set to 0 for a single ongoing ticket per conversation.',
      options:     {
        form: [
          {
            display:  'Thread Window (hours)',
            null:     false,
            name:     'kc_ringcentral_sms_thread_window_hours',
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
      title:       'RingCentral SMS Ticket Title Template',
      name:        'kc_ringcentral_sms_ticket_title_template',
      area:        'Kc::RingCentralSms',
      description: 'Template for new ticket titles. Use {phone} as a placeholder for the sender phone number.',
      options:     {
        form: [
          {
            display:  'Ticket Title Template',
            null:     false,
            name:     'kc_ringcentral_sms_ticket_title_template',
            tag:      'input',
            type:     'text',
          },
        ],
      },
      state:        'SMS from {phone}',
      preferences:  {
        permission: ['admin'],
      },
      frontend:     true,
    )

    Setting.create_if_not_exists(
      title:       'RingCentral SMS Poll Interval (seconds)',
      name:        'kc_ringcentral_sms_poll_interval_seconds',
      area:        'Kc::RingCentralSms',
      description: 'How often (in seconds) to poll the RingCentral message store for missed messages.',
      options:     {
        form: [
          {
            display:  'Poll Interval (seconds)',
            null:     false,
            name:     'kc_ringcentral_sms_poll_interval_seconds',
            tag:      'input',
            type:     'text',
          },
        ],
      },
      state:        60,
      preferences:  {
        permission: ['admin'],
      },
      frontend:     true,
    )
  end

  def down
    Setting.find_by(name: 'kc_ringcentral_sms_thread_window_hours')&.destroy
    Setting.find_by(name: 'kc_ringcentral_sms_ticket_title_template')&.destroy
    Setting.find_by(name: 'kc_ringcentral_sms_poll_interval_seconds')&.destroy
  end
end
