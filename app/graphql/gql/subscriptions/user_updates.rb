# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

module Gql::Subscriptions
  class UserUpdates < BaseSubscription
    description 'Updates to user records'

    include Gql::Subscriptions::Concerns::CanInitialResult

    unique_argument_id_key 'userId'

    argument :user_id, GraphQL::Types::ID, 'ID of the user to receive updates for'

    field :user, Gql::Types::UserType, description: 'Updated user'

    # Instance method: allow subscriptions only for users where the current user has read permission for.
    def authorized?(user_id:, initial:)
      ::Gql::ZammadSchema.authorized_object_from_id user_id, type: ::User, user: context.current_user
    end

    def subscribe(user_id:, initial:)
      return {} if !initial

      { user: Gql::ZammadSchema.object_from_id(user_id, type: ::User) }
    end

    def update(user_id:, initial:)
      { user: object }
    end
  end
end
