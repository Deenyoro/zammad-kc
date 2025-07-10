# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class Service::AI::Agent::Run::Context
  attr_reader :entity_object, :instruction_context, :entity_context, :entity_article

  def initialize(entity_object:, instruction_context:, entity_context:, entity_article: nil)
    @entity_object = entity_object
    @instruction_context = instruction_context || {}
    @entity_context = entity_context || {}
    @entity_article = entity_article
  end

  def prepare_instructions
    instruction = Service::AI::Agent::Run::Context::Instruction.new(
      instruction_context:,
    )

    instruction.prepare
  end

  def prepare_entity
    entity = Service::AI::Agent::Run::Context::Entity.new(
      entity_object:,
      entity_context:,
      entity_article:,
    )

    entity.prepare
  end
end
