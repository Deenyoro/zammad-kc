# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Concerns::RequiresTicketAgentPermission
  extend ActiveSupport::Concern

  included do

    def self.authorize(_obj, ctx)
      ctx.current_user.permissions?(['ticket.agent'])
    end

  end
end
