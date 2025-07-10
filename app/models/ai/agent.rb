# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class AI::Agent < ApplicationModel
  include ChecksHtmlSanitized
  include HasSearchIndexBackend
  include CanSelector
  include CanSearch
  include EnsuresNoRelatedObjects

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :note, length: { maximum: 250 }
  sanitized_html :note

  belongs_to :created_by, class_name: 'User'
  belongs_to :updated_by, class_name: 'User'

  ensures_no_related_objects_path 'ai.ai_agent', 'ai_agent_id'

  scope :working_on, lambda { |ticket|
    where(id: TriggerAIAgentJob.working_on(ticket))
  }
end
