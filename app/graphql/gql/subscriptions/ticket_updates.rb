# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Subscriptions
  class TicketUpdates < BaseSubscription
    description 'Updates to ticket records'

    include Gql::Subscriptions::Concerns::CanInitialResult

    unique_argument_id_key 'ticketId'

    argument :ticket_id, GraphQL::Types::ID, description: 'Ticket identifier'

    field :ticket, Gql::Types::TicketType, description: 'Updated ticket'

    def authorized?(ticket_id:, initial:)
      Gql::ZammadSchema.authorized_object_from_id ticket_id, type: ::Ticket, user: context.current_user
    end

    def subscribe(ticket_id:, initial:)
      return {} if !initial

      { ticket: Gql::ZammadSchema.object_from_id(ticket_id, type: ::Ticket) }
    end

    def update(ticket_id:, initial:)
      { ticket: object }
    end
  end
end
