# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Mutations
  class Ticket::Checklist::Base < BaseMutation
    include Gql::Concerns::EnsuresChecklistFeatureActive
    include Gql::Concerns::RequiresTicketAgentPermission

    description 'Base class for checklist mutations.'

    def self.authorize(_obj, ctx)
      ensure_checklist_feature_active!

      super
    end
  end
end
