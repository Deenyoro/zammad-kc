# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class AI::Agent::Type
  include Mixin::RequiredSubPaths

  def self.available_types
    @available_types ||= descendants.sort_by(&:name)
  end

  def self.available_type_data
    available_types.map { |x| x.new.data }
  end

  def data
    {
      id:                self.class.name.demodulize,
      name:,
      description:,
      definition:,
      action_definition:,
      form_schema:,
    }
  end

  def name
    raise 'not implemented'
  end

  def description
    raise 'not implemented'
  end

  def form_schema
    []
  end

  def definition
    {
      role_description:,
      instruction_context:,
      instruction:,
      entity_context:,
      result_structure:,
    }
  end

  def action_definition
    raise 'not implemented'
  end

  private

  def instruction
    raise 'not implemented'
  end

  def role_description
    raise 'not implemented'
  end

  def instruction_context
    {}
  end

  def entity_context
    {
      object_attributes: ['title'],
      articles:          'all',
    }
  end

  def result_structure
    raise 'not implemented'
  end
end
