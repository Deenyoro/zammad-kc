# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

module TouchesPerformReferences
  extend ActiveSupport::Concern

  included do
    before_create :touch_perform_references
    before_update :touch_perform_references
    before_destroy :touch_perform_references
  end

  def touch_perform_references
    return if !respond_to?(:perform) || perform.blank?

    ai_agent_ids = collect_ai_agent_ids_from_perform(perform)
    return if ai_agent_ids.empty?

    # Touch all found AI agents.
    AI::Agent.where(id: ai_agent_ids).each(&:touch)
  end

  private

  def collect_ai_agent_ids_from_perform(perform_data)
    return [] if !perform_data.is_a?(Hash)

    ai_agent_ids = []

    # Check current perform data
    ai_agent_id = perform_data.dig('ai.ai_agent', 'ai_agent_id')
    ai_agent_ids << ai_agent_id.to_i if ai_agent_id.present?

    # Check previous perform data (for updates)
    if respond_to?(:perform_was)
      ai_agent_id = perform_was.dig('ai.ai_agent', 'ai_agent_id')
      ai_agent_ids << ai_agent_id.to_i if ai_agent_id.present?
    end

    ai_agent_ids.uniq
  end

end
