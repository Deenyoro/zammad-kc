# frozen_string_literal: true

# KC: Setting and Scheduler for calling a human about unfixed escalations.
#
# The 20-minute delay, the overnight silence, and the morning resume are all
# enforced by the PBX connector's escalation policy, shared with the uptime
# alerts. This side only decides which tickets are still escalated.
#
# Safety: idempotent via create_if_not_exists.
class AddKcEscalationCalls < ActiveRecord::Migration[7.0]
  def up
    Setting.create_if_not_exists(
      title:       'KC Escalation Calls — Enabled',
      name:        'kc_escalation_call_enabled',
      area:        'Kc::Freepbx',
      description: 'Call a phone number when a ticket escalation has gone unfixed. Requires an active FreePBX connection.',
      options:     {},
      state:       false,
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    # Set the first time the job runs. Anything already escalated before
    # that moment is backlog, not a new escalation, and never rings.
    Setting.create_if_not_exists(
      title:       'KC Escalation Calls — Watching Since',
      name:        'kc_escalation_call_since',
      area:        'Kc::Freepbx',
      description: 'Escalations older than this are treated as pre-existing backlog and never trigger a call. Set automatically the first time escalation calling runs.',
      options:     {},
      state:       '',
      preferences: { permission: ['admin'] },
      frontend:    false,
    )

    Scheduler.create_if_not_exists(
      name:          'Call about unfixed KC escalations.',
      method:        'Kc::EscalationCallJob.perform_now',
      period:        60.seconds,
      prio:          2,
      active:        true,
      updated_by_id: 1,
      created_by_id: 1,
      last_run:      Time.current,
    )
  end

  def down
    Scheduler.find_by(name: 'Call about unfixed KC escalations.')&.destroy
    Setting.where(name: %w[kc_escalation_call_enabled kc_escalation_call_since]).destroy_all
  end
end
