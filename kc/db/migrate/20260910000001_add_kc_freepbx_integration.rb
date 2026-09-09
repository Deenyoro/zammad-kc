# frozen_string_literal: true

# KC: Settings and Scheduler for the FreePBX phone integration.
#
# RingCentral rings first and owns SMS for the whole system; calls it does
# not answer forward to FreePBX where the team rings. A call missed at that
# second layer gets the same handling as a missed RingCentral call — a
# ticket, and a text back to the caller sent through RingCentral.
#
# Creates Settings (area: Kc::Freepbx):
#   - kc_freepbx_missed_call_ticket             — boolean, default true
#   - kc_freepbx_missed_call_ticket_title       — string
#   - kc_freepbx_missed_call_autoreply          — boolean, default true
#   - kc_freepbx_missed_call_autoreply_message  — string
#   - kc_freepbx_missed_call_autoreply_from     — string, blank = default number
#
# Also adds the matching from-number setting for the RingCentral side, so
# either integration can text from any number configured in the system.
#
# Creates 1 Scheduler: Kc::PollFreepbxMissedCallsJob every 60 seconds.
#
# Safety: idempotent via create_if_not_exists.
class AddKcFreepbxIntegration < ActiveRecord::Migration[7.0]
  def up
    Setting.create_if_not_exists(
      title:       'KC FreePBX — Create Ticket on Missed Call',
      name:        'kc_freepbx_missed_call_ticket',
      area:        'Kc::Freepbx',
      description: 'Automatically create a ticket when the team misses an inbound call on FreePBX.',
      options:     {},
      state:       true,
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    Setting.create_if_not_exists(
      title:       'KC FreePBX — Missed Call Ticket Title',
      name:        'kc_freepbx_missed_call_ticket_title',
      area:        'Kc::Freepbx',
      description: 'Title for FreePBX missed call tickets. Use {phone} for the caller phone number.',
      options:     {},
      state:       'Missed call from {phone}',
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    Setting.create_if_not_exists(
      title:       'KC FreePBX — Auto-Reply SMS on Missed Call',
      name:        'kc_freepbx_missed_call_autoreply',
      area:        'Kc::Freepbx',
      description: 'Text the caller when the team misses their call on FreePBX. Sent through RingCentral.',
      options:     {},
      state:       true,
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    Setting.create_if_not_exists(
      title:       'KC FreePBX — Auto-Reply Message',
      name:        'kc_freepbx_missed_call_autoreply_message',
      area:        'Kc::Freepbx',
      description: 'The SMS sent to callers when the team misses their call on FreePBX.',
      options:     {},
      state:       'We are sorry for missing your call. A ticket has been created and our team will follow up with you shortly.',
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    Setting.create_if_not_exists(
      title:       'KC FreePBX — Auto-Reply From Number',
      name:        'kc_freepbx_missed_call_autoreply_from',
      area:        'Kc::Freepbx',
      description: 'Which number FreePBX missed call replies are texted from. Blank uses the default RingCentral number.',
      options:     {},
      state:       '',
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    Setting.create_if_not_exists(
      title:       'KC RingCentral — Missed Call Auto-Reply From Number',
      name:        'kc_ringcentral_sms_missed_call_autoreply_from',
      area:        'Kc::RingCentralSms',
      description: 'Which number RingCentral missed call replies are texted from. Blank uses the channel number.',
      options:     {},
      state:       '',
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    Scheduler.create_if_not_exists(
      name:          'Poll FreePBX missed calls.',
      method:        'Kc::PollFreepbxMissedCallsJob.perform_now',
      period:        60.seconds,
      prio:          2,
      active:        true,
      updated_by_id: 1,
      created_by_id: 1,
      last_run:      Time.current,
    )
  end

  def down
    Scheduler.find_by(name: 'Poll FreePBX missed calls.')&.destroy
    Setting.where("name LIKE 'kc_freepbx_%'").destroy_all
    Setting.find_by(name: 'kc_ringcentral_sms_missed_call_autoreply_from')&.destroy
  end
end
