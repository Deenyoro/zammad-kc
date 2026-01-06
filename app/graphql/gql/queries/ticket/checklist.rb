# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Queries
  class Ticket::Checklist < BaseQuery
    include Gql::Concerns::EnsuresChecklistFeatureActive
    include Gql::Concerns::RequiresTicketAgentPermission

    description 'Fetch ticket checklist'

    argument :ticket_id, ID, loads: Gql::Types::TicketType, description: 'Ticket ID'

    type Gql::Types::ChecklistType, null: true

    def self.authorize(_obj, ctx)
      ensure_checklist_feature_active!

      super
    end

    def resolve(ticket:)
      ::Checklist.find_by(ticket:)
    end
  end
end
