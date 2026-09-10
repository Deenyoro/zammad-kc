# frozen_string_literal: true

# KC: Durable bookkeeping for escalation calls.
#
# Which tickets have already been rung for, and which alert keys the PBX is
# holding, used to live in Rails.cache. A cache flush or a pod restart wiped
# it and rang everyone again for the same escalation. It is a Setting now.
#
# Safety: idempotent via create_if_not_exists.
class AddKcEscalationCallState < ActiveRecord::Migration[7.0]
  def up
    Setting.create_if_not_exists(
      title:       'KC Escalation Calls — State',
      name:        'kc_escalation_call_state',
      area:        'Kc::Freepbx',
      description: 'Internal bookkeeping for escalation calls: tickets already called and alerts held at the PBX. Managed automatically.',
      options:     {},
      state:       '',
      preferences: { permission: ['admin'] },
      frontend:    false,
    )
  end

  def down
    Setting.find_by(name: 'kc_escalation_call_state')&.destroy
  end
end
