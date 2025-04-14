# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

module Gql::Subscriptions
  class Ticket::AIAssistance::SummaryUpdates < BaseSubscription

    description 'Updates to triggered AI assistance summary'

    argument :ticket_id, GraphQL::Types::ID, description: 'Ticket identifier'
    argument :locale, String, 'The locale to use, e.g. "de-de".'

    field :summary, Gql::Types::Ticket::AIAssistance::SummaryType, description: 'Different parts of the generated summary'
    field :reason, String, description: 'Reason for the result of the summary generation' # TODO: only for debugging/admins?
    field :fingerprint_md5, String, description: 'MD5 digest of the complete summary content'
    field :error, Gql::Types::AsyncExecutionErrorType, description: 'Error that occurred during the execution of the async job'

    def authorized?(ticket_id:, locale:)
      Service::CheckFeatureEnabled.new(name: 'ai_assistance_ticket_summary', exception: false).execute &&
        Service::CheckFeatureEnabled.new(name: 'ai_provider', exception: false).execute &&
        Gql::ZammadSchema.authorized_object_from_id(ticket_id, type: ::Ticket, user: context.current_user, query: :agent_read_access?)
    end

    def update(ticket_id:, locale:)
      if object[:error]
        return {
          error: object[:error]
        }
      end

      {
        summary:         object[:summary],
        reason:          object[:reason],
        fingerprint_md5: object[:fingerprint_md5],
      }
    end
  end
end
