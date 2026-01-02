# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Subscriptions
  class Ticket::CustomerTicketsByFilterUpdates < BaseSubscription
    description 'Updated customer tickets by filter'

    argument :customer_id, GraphQL::Types::ID, required: false, description: 'Filter by customer', loads: Gql::Types::UserType

    field :list_changed, Boolean, description: 'Signals that the customer tickets list has changed'

    def authorized?(...)
      context.current_user.permissions?(['ticket.agent'])
    end

    def update(customer:)
      { list_changed: true }
    end
  end
end
