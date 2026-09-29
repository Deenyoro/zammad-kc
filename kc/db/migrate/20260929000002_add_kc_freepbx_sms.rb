# KC: FreePBX text messaging — settings, article type and poll scheduler.
#
# Texts flow through the KC PBX connector, which fronts the PBX's SMS
# module (Sangoma SMS with SIPStation DIDs, or the open-source smsconnector
# module with a third-party carrier). Off by default: the connector has to
# implement the SMS endpoints (see Kc::FreepbxApi) before it is useful, and
# the "New SMS Message (FreePBX)" menu entry only appears once it is on.
#
# Safety:
#   - Idempotent via create_if_not_exists
#   - Skipped on fresh installs (system_init_done guard)
class AddKcFreepbxSms < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Setting.create_if_not_exists(
      title:       'KC FreePBX — Text Messaging',
      name:        'kc_freepbx_sms_enabled',
      area:        'Kc::Freepbx',
      description: 'Send and receive text messages through the FreePBX connector. Adds "New SMS Message (FreePBX)" for agents and makes the PBX numbers available as reply and auto-reply senders.',
      options:     {
        form: [
          {
            display: 'Text Messaging',
            null:    false,
            name:    'kc_freepbx_sms_enabled',
            tag:     'boolean',
            options: { true => 'yes', false => 'no' },
          },
        ],
      },
      state:       false,
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    Setting.create_if_not_exists(
      title:       'KC FreePBX — SMS Ticket Title Template',
      name:        'kc_freepbx_sms_ticket_title_template',
      area:        'Kc::Freepbx',
      description: 'Template for new ticket titles. Use {phone} as a placeholder for the sender phone number.',
      options:     {
        form: [
          { display: 'Ticket Title Template', null: false, name: 'kc_freepbx_sms_ticket_title_template', tag: 'input', type: 'text' },
        ],
      },
      state:       'SMS from {phone}',
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    Setting.create_if_not_exists(
      title:       'KC FreePBX — SMS Thread Window (hours)',
      name:        'kc_freepbx_sms_thread_window_hours',
      area:        'Kc::Freepbx',
      description: 'Number of hours after the last message before a new ticket is created for the same phone number pair. Set to 0 for a single ongoing ticket per conversation.',
      options:     {
        form: [
          { display: 'Thread Window (hours)', null: false, name: 'kc_freepbx_sms_thread_window_hours', tag: 'input', type: 'text' },
        ],
      },
      state:       24,
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    Setting.create_if_not_exists(
      title:       'KC FreePBX — SMS Context Messages',
      name:        'kc_freepbx_sms_context_messages',
      area:        'Kc::Freepbx',
      description: 'How many earlier messages of the conversation to attach as an internal context note when a new SMS ticket is opened by the integration. 0 disables.',
      options:     {
        form: [
          { display: 'Context Messages', null: false, name: 'kc_freepbx_sms_context_messages', tag: 'input', type: 'text' },
        ],
      },
      state:       5,
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    Setting.create_if_not_exists(
      title:       'KC FreePBX — Default SMS Number',
      name:        'kc_freepbx_sms_default_number',
      area:        'Kc::Freepbx',
      description: 'PBX number preselected when an agent starts a new FreePBX text conversation. Blank uses the first number the connector reports.',
      options:     {
        form: [
          { display: 'Default SMS Number', null: true, name: 'kc_freepbx_sms_default_number', tag: 'input', type: 'text' },
        ],
      },
      state:       '',
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    Ticket::Article::Type.create_if_not_exists(
      name:          'freepbx_sms_message',
      communication: true,
      updated_by_id: 1,
      created_by_id: 1,
    )

    Scheduler.create_if_not_exists(
      name:          'Poll FreePBX SMS messages.',
      method:        'Kc::PollFreepbxSmsMessagesJob.perform_now',
      period:        60.seconds,
      prio:          4,
      active:        true,
      updated_by_id: 1,
      created_by_id: 1,
      last_run:      Time.current,
    )
  end

  def down
    Scheduler.find_by(name: 'Poll FreePBX SMS messages.')&.destroy
    %w[
      kc_freepbx_sms_enabled
      kc_freepbx_sms_ticket_title_template
      kc_freepbx_sms_thread_window_hours
      kc_freepbx_sms_context_messages
      kc_freepbx_sms_default_number
    ].each { |name| Setting.find_by(name: name)&.destroy }
  end
end
