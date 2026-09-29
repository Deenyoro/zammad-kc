# KC: Setting for call notes on open SMS threads.
#
# When on, every call RingCentral or FreePBX took or placed for a number
# that has an open SMS ticket is written to that ticket as an internal
# note (Kc::CallHistoryFiling#note_call_on_sms_thread). The note is a
# record only: the ticket keeps its state, nobody is notified, and a
# closed thread gets nothing.
#
# Safety:
#   - Idempotent via create_if_not_exists
class AddKcSmsCallThreadNotesSetting < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Setting.create_if_not_exists(
      title:       'RingCentral SMS: Note Calls on Open Text Threads',
      name:        'kc_ringcentral_sms_call_thread_notes',
      area:        'Kc::RingCentralSms',
      description: 'Add an internal note to the open SMS ticket for a number whenever that number is called from, or calls, RingCentral or FreePBX. The ticket state is not changed and closed tickets are left alone.',
      options:     {
        form: [
          {
            display: 'Note Calls on Open Text Threads',
            null:    false,
            name:    'kc_ringcentral_sms_call_thread_notes',
            tag:     'boolean',
            options: {
              true  => 'yes',
              false => 'no',
            },
          },
        ],
      },
      state:       true,
      preferences: {
        permission: ['admin'],
      },
      frontend:    true,
    )
  end

  def down
    Setting.find_by(name: 'kc_ringcentral_sms_call_thread_notes')&.destroy
  end
end
