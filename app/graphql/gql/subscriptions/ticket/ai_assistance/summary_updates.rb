# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

module Gql::Subscriptions
  class Ticket::AIAssistance::SummaryUpdates < BaseSubscription

    description 'Updates to triggered AI assistance summary'

    argument :ticket_id, GraphQL::Types::ID, description: 'Ticket identifier'
    argument :locale, String, 'The locale to use, e.g. "de-de".'

    field :summary, Gql::Types::Ticket::AIAssistance::SummaryType, description: 'Different parts of the generated summary'
    field :reason, String, description: 'Reason for the result of the summary generation'
    field :fingerprint_md5, String, description: 'MD5 digest of the complete summary content'
    field :error, Gql::Types::AsyncExecutionErrorType, description: 'Error that occurred during the execution of the async job'
    field :relevant_for_current_user, Boolean, description: 'Indicates if the summary is relevant for the current user'

    def authorized?(ticket_id:, locale:)
      Service::CheckFeatureEnabled.new(name: 'ai_assistance_ticket_summary', exception: false).execute &&
        Service::CheckFeatureEnabled.new(name: 'ai_provider', exception: false).execute &&
        Gql::ZammadSchema.authorized_object_from_id(ticket_id, type: ::Ticket, user: context.current_user, query: :agent_read_access?)
    end

    def update(ticket_id:, locale:)
      return { error: object[:error] } if object[:error]

      # Fetch last article for the ticket to determine the relevance of the summary.
      last_article = ::Ticket::Article.last_customer_agent_article(Gql::ZammadSchema.internal_id_from_id(ticket_id, type: ::Ticket))

      {
        summary:                   object[:summary],
        reason:                    object[:reason],
        fingerprint_md5:           object[:fingerprint_md5],
        relevant_for_current_user: last_article&.author&.id != context.current_user.id,
      }
    end
  end
end
