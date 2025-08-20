# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

module Gql::Mutations
  class AIAssistance::TextTools::Run < BaseMutation
    description 'Run an AI text tool service on the supplied text or HTML content'

    argument :input, String, description: 'Text or HTML content to run the text tool service on'
    argument :text_tool_id, GraphQL::Types::ID, loads: Gql::Types::AI::TextToolType, description: 'ID of the AI text tool to be executed.'
    argument :template_render_context, Gql::Types::Input::TemplateRenderContextInputType, description: 'Context data for the text tool instruction rendering, e.g. customer data.'

    field :output, String, description: 'Returned text'

    def resolve(input:, text_tool:, template_render_context:)
      output = Service::AIAssistance::TextTools.new(
        input:,
        text_tool:,
        template_render_context: template_render_context.to_context_hash,
        current_user:            context.current_user,
      ).execute

      {
        output: output[:content],
      }
    end
  end
end
