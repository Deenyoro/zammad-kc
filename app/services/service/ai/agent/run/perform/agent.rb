# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class Service::AI::Agent::Run::Perform::Agent < SimpleDelegator

  attr_reader :ai_result

  def initialize(ai_agent:, ai_result:)
    @ai_result = ai_result

    super(ai_agent)
  end

  # For now we are directly returning the mapping
  def perform
    @perform ||= begin
      action_mapping = prepare_action_mapping

      rendered_mapping = NotificationFactory::Renderer.new(
        objects:                { ai_agent_result: perform_ai_result_object },
        template:               action_mapping.to_json,
        escape:                 false,
        url_encode:             true,
        ignore_missing_objects: true,
      ).render(debug_errors: false)

      JSON.parse(rendered_mapping)
    end
  end

  def class
    __getobj__.class
  end

  private

  def prepare_action_mapping
    # Start with the base mapping
    mapping = execution_action_definition['mapping'] || {}

    # Process conditions if they exist
    conditions = execution_action_definition['conditions']
    return mapping if ai_result_content.blank? || conditions.blank?

    conditions.each do |item|
      next if item['condition'].blank? || item['mapping'].blank?

      if condition_matches?(item['condition'])
        mapping.merge!(item['mapping'])
      end
    end

    mapping
  end

  def condition_matches?(condition)
    return false if !condition.is_a?(Hash)

    ai_result_object = perform_ai_result_object
    return false if ai_result_object.nil?

    condition.each do |key, expected_value|
      return false if !ai_result_object.respond_to?(key.to_sym)

      actual_value = ai_result_object.send(key.to_sym)

      # If the key doesn't exist, the condition doesn't match.
      return false if actual_value.nil?

      return false if actual_value != expected_value
    end

    true
  end

  # Get a content object from the stored AI result for the usage in the template renderer.
  def perform_ai_result_object
    return if ai_result_content.blank?

    @perform_ai_result_object ||= if execution_definition['result_structure'].blank?
                                    result_struct = Struct.new(:content)
                                    result_struct.new(ai_result_content)
                                  else
                                    result_struct = Struct.new(*execution_definition['result_structure'].keys.map(&:to_sym))

                                    # Ensure values are passed in the correct order by mapping them to the result_structure keys
                                    values = execution_definition['result_structure'].keys.map { |key| ai_result_content[key] }
                                    result_struct.new(*values)
                                  end
  end

  def ai_result_content
    @ai_result_content ||= ai_result&.content
  end
end
