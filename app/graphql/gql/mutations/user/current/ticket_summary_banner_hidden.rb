# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

module Gql::Mutations
  class User::Current::TicketSummaryBannerHidden < BaseMutation
    description 'Update user profile ticket summary banner hidden setting'

    argument :hidden, Boolean, description: 'The new hidden state of setting'

    field :success, Boolean, null: false, description: 'Profile ticket summary banner setting updated successfully?'

    def self.authorize(_obj, ctx)
      ctx.current_user.permissions?('ticket.agent')
    end

    def resolve(hidden:)
      user = context.current_user
      user.preferences['ticket_summary_banner_hidden'] = hidden
      user.save!

      { success: true }
    end
  end
end
