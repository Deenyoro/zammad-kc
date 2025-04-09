# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

module Gql::Mutations
  class Ticket::Checklist::Add < Ticket::Checklist::Base
    description 'Create an empty checklist or a checklist based on a template for a ticket.'

    argument :ticket_id, GraphQL::Types::ID, loads: Gql::Types::TicketType, description: 'Ticket to create the new checklist for.'
    argument :template_id, GraphQL::Types::ID, required: false, description: 'Checklist template ID to base the ticket checklist on.'
    argument :create_first_item, GraphQL::Types::Boolean, required: false, description: 'Create the first item in the checklist (only if no template is used).'

    field :checklist, Gql::Types::ChecklistType, null: true, description: 'Created checklist'

    def authorized?(ticket:, create_first_item: false, template_id: nil)
      Setting.get('checklist') && pundit_authorized?(ticket, :agent_update_access?)
    end

    def resolve(ticket:, create_first_item: false, template_id: nil)
      checklist = if template_id
                    template = Gql::ZammadSchema.verified_object_from_id(template_id, type: ::ChecklistTemplate)

                    Checklist.create_from_template!(ticket, template)
                  elsif create_first_item
                    Checklist.create_fresh!(ticket)
                  else
                    Checklist.create!(ticket:)
                  end

      { checklist: }
    end
  end
end
