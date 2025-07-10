# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class Service::AI::Agent::Run::Context::Instruction::ObjectAttributes::Options < Service::AI::Agent::Run::Context::Instruction::ObjectAttributes
  def self.applicable?(object_attribute)
    object_attribute.data_option[:options].present?
  end

  def prepare_for_instruction
    if options.is_a?(Hash)
      return prepare_hash_options
    end

    prepare_array_options
  end

  private

  def prepare_hash_options
    if filter_values.present?
      filter_values.filter_map do |value|
        next if value.blank?

        if options.key?(value)
          {
            value: value,
            label: options[value]
          }
        end
      end
    else
      options.map do |value, label|
        {
          value: value,
          label: label
        }
      end
    end
  end

  def prepare_array_options
    if filter_values.present?
      collect_matching_options(options, filter_values)
    else
      collect_all_options_flat(options)
    end
  end

  def collect_matching_options(options, filter_values)
    result = []
    options.each do |option|
      if filter_values.include?(option['value'])
        result << build_option_structure(option).except(:children)
      end
      if option['children'].present?
        result += collect_matching_options(option['children'], filter_values)
      end
    end
    result
  end

  def collect_all_options_flat(options)
    result = []
    options.each do |option|
      result << build_option_structure(option).except(:children)
      if option['children'].present?
        result += collect_all_options_flat(option['children'])
      end
    end
    result
  end

  def build_option_structure(option)
    result = {
      value: option['value'],
      label: option['value'],
    }
    if option['children'].present?
      result[:children] = option['children'].map { |child| build_option_structure(child) }
    end
    result
  end

  def options
    @options ||= object_attribute.data_option[:options]
  end
end
