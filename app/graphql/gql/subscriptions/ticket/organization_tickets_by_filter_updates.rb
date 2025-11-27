# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

module Gql::Subscriptions
  class Ticket::OrganizationTicketsByFilterUpdates < BaseSubscription
    description 'Updated organization tickets by filter'

    argument :organization_id, GraphQL::Types::ID, required: false, description: 'Filter by organization', loads: Gql::Types::OrganizationType

    field :list_changed, Boolean, description: 'Signals that the organization tickets list has changed'

    def authorized?(...)
      context.current_user.permissions?(['ticket.agent'])
    end

    def update(organization:)
      { list_changed: true }
    end
  end
end
