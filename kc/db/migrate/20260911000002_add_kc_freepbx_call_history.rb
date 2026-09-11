# frozen_string_literal: true

# KC: Setting for filing every inbound FreePBX call as a closed phone ticket.
#
# Calls that came through RingCentral are filed by the RingCentral history
# job (which also records which PBX extension answered). This covers the
# rest: calls dialled straight to the PBX number.
#
# Safety: idempotent via create_if_not_exists.
class AddKcFreepbxCallHistory < ActiveRecord::Migration[7.0]
  def up
    Setting.create_if_not_exists(
      title:       'KC FreePBX — Import Call History as Closed Tickets',
      name:        'kc_freepbx_call_history_ticket',
      area:        'Kc::Freepbx',
      description: 'File every inbound call that reached FreePBX directly (not through RingCentral) as a closed phone ticket, backdated to the call time, with no notifications.',
      options:     {},
      state:       true,
      preferences: { permission: ['admin'] },
      frontend:    true,
    )
  end

  def down
    Setting.find_by(name: 'kc_freepbx_call_history_ticket')&.destroy
  end
end
