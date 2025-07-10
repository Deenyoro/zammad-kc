# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class Service::AI::Agent::Run::Context::Instruction::ObjectAttributes::Relation < Service::AI::Agent::Run::Context::Instruction::ObjectAttributes
  ALLOWED_RELATIONS = {
    'Group'          => 'Group',
    'TicketState'    => 'Ticket::State',
    'TicketPriority' => 'Ticket::Priority',
  }.freeze

  def self.applicable?(object_attribute)
    object_attribute.data_option[:relation].present? && ALLOWED_RELATIONS.key?(object_attribute.data_option[:relation])
  end

  def prepare_for_instruction
    items.map do |item|
      {
        value: item.id,
        label: item.name,
      }
    end
  end

  private

  def items
    @items ||= begin
      if filter_values.present?
        relation_type.where(active: true).where(id: filter_values)
      else
        relation_type.where(active: true)
      end
    end
  end

  def relation_type
    relation_name = ALLOWED_RELATIONS[object_attribute.data_option[:relation]]
    relation_name.constantize
  end
end
