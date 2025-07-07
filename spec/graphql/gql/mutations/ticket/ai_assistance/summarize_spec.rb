# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Gql::Mutations::Ticket::AIAssistance::Summarize, :aggregate_failures, type: :graphql do
  context 'when summarizing a ticket', authenticated_as: :agent do
    let(:agent)           { create(:agent, groups: [ticket.group]) }
    let(:ticket)          { create(:ticket) }
    let(:ticket_article)  { create(:ticket_article, ticket: ticket) }
    let(:expected_cache)  { nil }

    let(:query) do
      <<~MUTATION
        mutation ticketAIAssistanceSummarize($ticketId: ID!) {
          ticketAIAssistanceSummarize(ticketId: $ticketId) {
            summary {
              problem
              conversationSummary
              openQuestions
              suggestions
            }
            fingerprintMd5
            relevantForCurrentUser
          }
        }
      MUTATION
    end

    let(:variables) { { ticketId: gql.id(ticket) } }

    before do
      Setting.set('ai_assistance_ticket_summary', true)
      Setting.set('ai_provider', 'zammad_ai')

      ticket_article

      if expected_cache
        AI::StoredResult.create!(
          content: expected_cache,
          version: AI::Service::TicketSummarize.persistent_version({ ticket: }, Locale.find_by(locale: agent.locale)),
          **AI::Service::TicketSummarize.persistent_lookup_attributes({ ticket: }, Locale.find_by(locale: agent.locale)),
        )
      end

      gql.execute(query, variables: variables)
    end

    context 'when the summary is already in the cache' do
      let(:expected_cache) do
        {
          'problem'        => 'example',
          'summary'        => 'example',
          'open_questions' => ['example'],
          'suggestions'    => ['example'],
          'reason'         => 'example',
        }
      end

      it 'returns the cached summary' do
        expect(gql.result.data).to include(
          summary:                eq({
                                       'conversationSummary' => 'example',
                                       'openQuestions'       => ['example'],
                                       'problem'             => 'example',
                                       'suggestions'         => ['example'],
                                     }),
          fingerprintMd5:         eq(Digest::MD5.hexdigest(expected_cache.slice('problem', 'summary', 'open_questions', 'suggestions').to_s)),
          relevantForCurrentUser: true,
        )
      end
    end

    context 'when the summary is not in the cache', performs_jobs: true do
      it 'returns nil' do
        expect(gql.result.data).to include(
          summary:        be_nil,
          fingerprintMd5: be_nil,
        )
      end

      it 'enqueues a background job to generate the summary' do
        expect(TicketAIAssistanceSummarizeJob).to have_been_enqueued
          .with(ticket, agent.locale)
      end
    end

    it_behaves_like 'graphql responds with error if unauthenticated'
  end
end
