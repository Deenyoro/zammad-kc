# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

module Gql::Mutations
  class Organization::NoteUpdate < BaseMutation
    description 'Update the note field of an organization.'

    argument :id, GraphQL::Types::ID, description: 'The organization ID', as: :current_organization, loads: Gql::Types::OrganizationType
    argument :note, String, description: 'The organization note'

    field :organization, Gql::Types::OrganizationType, description: 'The updated organization.'

    # TODO/FIXME: Remove this again when we have a proper solution to deal with Pundit stuff in GraphQL mutations.
    def self.authorize(_obj, ctx)
      ctx.current_user.permissions?(['admin.organization', 'ticket.agent'])
    end

    def resolve(current_organization:, note:)
      { organization: forced_update(current_organization:, note:) }
    end

    private

    def forced_update(current_organization:, note:)
      current_organization.with_lock do
        current_organization.update!({ note: })
      end

      current_organization
    end
  end
end
