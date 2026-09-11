# KC: Settings for the conversation-context note on new integration tickets.
#
# When RingCentral SMS or Teams opens a NEW ticket, the last N messages of
# that conversation (both directions, from before the message that opened
# the ticket) are added as one internal note so the agent sees what led up
# to it. 0 disables the note.
#
# Safety:
#   - Idempotent via create_if_not_exists
class AddKcConversationContextSettings < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Setting.create_if_not_exists(
      title:       'RingCentral SMS Context Messages',
      name:        'kc_ringcentral_sms_context_messages',
      area:        'Kc::RingCentralSms',
      description: 'How many earlier messages of the conversation to attach as an internal context note when a new SMS ticket is opened by the integration. 0 disables.',
      options:     {
        form: [
          {
            display: 'Context Messages',
            null:    false,
            name:    'kc_ringcentral_sms_context_messages',
            tag:     'input',
            type:    'text',
          },
        ],
      },
      state:        5,
      preferences:  {
        permission: ['admin'],
      },
      frontend:     true,
    )

    Setting.create_if_not_exists(
      title:       'Teams Chat Context Messages',
      name:        'kc_teams_chat_context_messages',
      area:        'Kc::TeamsChat',
      description: 'How many earlier messages of the chat to attach as an internal context note when a new Teams ticket is opened by the integration. 0 disables.',
      options:     {
        form: [
          {
            display: 'Context Messages',
            null:    false,
            name:    'kc_teams_chat_context_messages',
            tag:     'input',
            type:    'text',
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
    Setting.find_by(name: 'kc_ringcentral_sms_context_messages')&.destroy
    Setting.find_by(name: 'kc_teams_chat_context_messages')&.destroy
  end
end
