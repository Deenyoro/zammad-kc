# KC: Add settings for RingCentral missed call ticket creation and auto-reply.
#
# Safety:
#   - Idempotent via create_if_not_exists
class AddKcRingcentralMissedCallSettings < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Setting.create_if_not_exists(
      title:       'RingCentral: Create Ticket on Missed Call',
      name:        'kc_ringcentral_sms_missed_call_ticket',
      area:        'Kc::RingCentralSms',
      description: 'Automatically create a ticket when an inbound RingCentral call is missed.',
      options:     {
        form: [
          {
            display:  'Create Ticket on Missed Call',
            null:     false,
            name:     'kc_ringcentral_sms_missed_call_ticket',
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
      title:       'RingCentral: Missed Call Ticket Title Template',
      name:        'kc_ringcentral_sms_missed_call_ticket_title',
      area:        'Kc::RingCentralSms',
      description: 'Template for missed call ticket titles. Use {phone} for the caller phone number.',
      options:     {
        form: [
          {
            display:  'Missed Call Ticket Title',
            null:     false,
            name:     'kc_ringcentral_sms_missed_call_ticket_title',
            tag:      'input',
            type:     'text',
          },
        ],
      },
      state:        'Missed call from {phone}',
      preferences:  {
        permission: ['admin'],
      },
      frontend:     true,
    )

    Setting.create_if_not_exists(
      title:       'RingCentral: Auto-Reply SMS on Missed Call',
      name:        'kc_ringcentral_sms_missed_call_autoreply',
      area:        'Kc::RingCentralSms',
      description: 'Automatically send an SMS reply to the caller when a RingCentral call is missed.',
      options:     {
        form: [
          {
            display:  'Auto-Reply SMS on Missed Call',
            null:     false,
            name:     'kc_ringcentral_sms_missed_call_autoreply',
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
      title:       'RingCentral: Missed Call Auto-Reply Message',
      name:        'kc_ringcentral_sms_missed_call_autoreply_message',
      area:        'Kc::RingCentralSms',
      description: 'The SMS message sent to callers when their call is missed.',
      options:     {
        form: [
          {
            display:  'Auto-Reply Message',
            null:     false,
            name:     'kc_ringcentral_sms_missed_call_autoreply_message',
            tag:      'input',
            type:     'text',
          },
        ],
      },
      state:        'We are sorry for missing your call. A ticket has been created and our team will follow up with you shortly.',
      preferences:  {
        permission: ['admin'],
      },
      frontend:     true,
    )
  end

  def down
    Setting.find_by(name: 'kc_ringcentral_sms_missed_call_ticket')&.destroy
    Setting.find_by(name: 'kc_ringcentral_sms_missed_call_ticket_title')&.destroy
    Setting.find_by(name: 'kc_ringcentral_sms_missed_call_autoreply')&.destroy
    Setting.find_by(name: 'kc_ringcentral_sms_missed_call_autoreply_message')&.destroy
  end
end
