# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class Sequencer::Unit::Import::Zendesk::ObjectAttribute::Skip < Sequencer::Unit::Base

  uses :model_class, :sanitized_name
  provides :action

  # Skip fields which already exists and not editable.
  def process
    attribute = object_attribute_for_name

    return if !attribute || attribute.editable

    logger.info { "Skipping. Default field '#{attribute}' found for field '#{sanitized_name}'." }
    state.provide(:action, :skipped)
  end

  private

  def object_attribute_for_name
    ObjectManager::Attribute.get(
      object: model_class.to_s,
      name:   sanitized_name
    )
  end
end
