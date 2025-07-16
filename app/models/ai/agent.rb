# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

##
# AI::Agent is a model that represents an AI agent with different strcutre parts:
#
# Definition:
#
# `role_description``: 'You have the role of doing something.',
# `instruction``: '- You should do this.
# - You should the other things.
# - ...',
# `instruction_context`: {
#    object_attributes: {
#      group_id: [3, 4, 5],
#      state_id: [1, 2, 3],
#      custom_treeselect: ['Category 1', 'Category 2', 'Category 1::Sub 1'],
#    }
#  }, // Informations which are added to the instructions (e.g. relevant group information for ticket group dispatching).
# `entity_context`: {
#    object_attributes: ['title', 'priority_id'], // All attributes of the object are possible.
#    articles: 'last|all', // The last article (current trigger article) or all articles of the object.
#  },
#  `result_structure`: {
#    group_id: 'integer',
#    is_real_question: 'boolean',
#  }, // JSON-Result structure is optional, it can also only be text.
#
# Action definition:
#
# The `ai_agent_result.example` will be replaced with the value from the AI service call, but also static values
# are possible.
#
# `mapping`: {
#   'ticket.group_id' => {
#     'value' => '#{ai_agent_result.group_id}'
#   },
# }, // Mapping of the result to the object attributes in perform changes syntax style.
#
# `conditions`: [
#   {
#     condition: {
#       is_real_question: false
#     },
#     mapping: {
#       'ticket.state' => {
#         'value' => 'closed'
#       },
#     }
#   }
# ], // Conditions are optional, they are used to check if the mapping should be executed.
#
# The mappings from the condition will be added to the general mapping and executed together.
#

class AI::Agent < ApplicationModel
  include ChecksHtmlSanitized
  include HasSearchIndexBackend
  include CanSelector
  include CanSearch
  include EnsuresNoRelatedObjects
  include AI::Agent::Assets
  include ChecksClientNotification

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
