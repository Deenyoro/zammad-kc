# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

module Gql::Types::Ticket::AIAssistance
  class SummaryType < Gql::Types::BaseObject
    description 'The ticket summary'

    field :problem, String, null: true
    field :conversation_summary, String, null: true
    field :open_questions, [String], null: true
    field :suggestions, [String], null: true
  end
end
