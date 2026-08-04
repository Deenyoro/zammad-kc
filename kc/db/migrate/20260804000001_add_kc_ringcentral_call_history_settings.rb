# KC: Add setting for RingCentral call history import.
#
# When enabled, Kc::PollRingcentralCallHistoryJob polls the RingCentral
# call log and files every completed voice call as a CLOSED ticket with
# article type 'phone' (backdated to the call time) — so call history
# counts toward per-organization ticket reporting without alerting anyone.
# Missed inbound calls stay owned by the missed-call feature, which
# creates OPEN tickets for follow-up.
#
# Safety:
#   - Idempotent via create_if_not_exists
class AddKcRingcentralCallHistorySettings < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Setting.create_if_not_exists(
      title:       'RingCentral: Import Call History as Closed Tickets',
      name:        'kc_ringcentral_call_history_ticket',
      area:        'Kc::RingCentralSms',
      description: 'Automatically file every completed RingCentral voice call as a closed phone ticket (backdated to the call time, no notifications). Missed inbound calls remain handled by the missed call feature.',
      options:     {
        form: [
          {
            display:  'Import Call History as Closed Tickets',
            null:     false,
            name:     'kc_ringcentral_call_history_ticket',
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
    Setting.find_by(name: 'kc_ringcentral_call_history_ticket')&.destroy
  end
end
