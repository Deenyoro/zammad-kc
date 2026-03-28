# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Types::OnlineNotificationStandalone
  class DataType < Gql::Types::BaseObject
    description 'Data payload of the standalone online notifications'

    field :total, Integer
    field :failed_count, Integer

  end
end
