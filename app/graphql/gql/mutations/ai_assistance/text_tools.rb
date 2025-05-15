# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

module Gql::Mutations
  class AIAssistance::TextTools < BaseMutation
    description 'Run an AI text tool service on the supplied text or HTML content'

    argument :input, String, description: 'Text or HTML content to run the text tool service on'
    argument :service_type, Gql::Types::Enum::AITextToolServiceType, description: 'The text tool service to use'

    field :output, String, description: 'Returned text'

    def resolve(input:, service_type:)
      output = Service::AIAssistance::TextTools.new(
        input:,
        service_type:,
        current_user: context.current_user,
      ).execute

      {
        output:,
      }
    end
  end
end
