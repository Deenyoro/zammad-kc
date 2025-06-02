# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

module Gql::Mutations
  class Ticket::Checklist::ItemsAdd < Ticket::Checklist::Base
    description 'Add checklist items.'

    argument :checklist_id, GraphQL::Types::ID, loads: Gql::Types::ChecklistType, description: 'ID of the ticket checklist to update or create an item for.'
    argument :input, [Gql::Types::Input::Ticket::Checklist::ItemInputType], description: 'Input field values of the ticket checklist item.'

    field :success, Boolean, null: false, description: 'Was the mutation successful?'
    field :checklist, Gql::Types::ChecklistType, null: false, description: 'Updated checklist.'

    def authorized?(checklist:, input:)
      pundit_authorized?(Checklist::Item.new(checklist:), :create?) && super
    end

    def resolve(checklist:, input:)
      input.each do |item_input|
        checklist.items.create!(item_input.to_h)
      end

      {
        success:   true,
        checklist: checklist.reload
      }
    end
  end
end
