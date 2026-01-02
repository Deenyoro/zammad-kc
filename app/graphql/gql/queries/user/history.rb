# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Queries
  class User::History < BaseQuery
    description 'Fetch history of a user'

    argument :user_id, ID, loads: Gql::Types::UserType, description: 'User ID'

    type [Gql::Types::HistoryGroupType], null: false

    def self.authorize(_obj, ctx)
      ctx.current_user.permissions?(['ticket.agent', 'admin.user'])
    end

    def resolve(user:)
      Service::History::Group
        .new(current_user: context.current_user)
        .execute(object: user)
    end
  end
end
