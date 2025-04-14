# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

module Gql::Mutations
  class Ticket::AIAssistance::Summarize < BaseMutation
    description 'Return current summary or trigger generation in the background'

    argument :ticket_id, GraphQL::Types::ID, loads: Gql::Types::TicketType, description: 'The ticket to fetch the summary for'

    field :summary, Gql::Types::Ticket::AIAssistance::SummaryType, description: 'Different parts of the generated summary'
    field :reason, String, description: 'Reason for the result of the summary generation'
    field :fingerprint_md5, String, description: 'MD5 digest of the complete summary content'

    def authorized?(ticket:)
      pundit_authorized?(ticket, :agent_read_access?)
    end

    # TODO: The current cache situation is more a first PoC, it will change to an persistent store.

    def resolve(ticket:)
      Service::CheckFeatureEnabled.new(name: 'ai_assistance_ticket_summary').execute
      Service::CheckFeatureEnabled.new(name: 'ai_provider', custom_error_message: __('AI provider is not configured.')).execute

      cache_key = AI::Service::TicketSummarize.cache_key(ticket, context.current_user.locale)
      cache     = Rails.cache.read(cache_key)

      if cache.present?
        return {
          summary:         {
            problem:              cache['problem'],
            conversation_summary: cache['summary'],
            open_questions:       cache['open_questions'],
            suggestions:          cache['suggestions'],
          },
          reason:          cache['reason'],
          fingerprint_md5: Digest::MD5.hexdigest(cache.slice('problem', 'summary', 'open_questions', 'suggestions').to_s),
        }
      end

      # Trigger background job to generate the summary.
      TicketAIAssistanceSummarizeJob.perform_later(ticket, context.current_user.locale)

      {
        summary: nil,
        reason:  nil,
      }
    end
  end
end
