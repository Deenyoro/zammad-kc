# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Gql::Subscriptions::Ticket::AIAssistance::SummaryUpdates, authenticated_as: :agent, type: :graphql do
  let(:agent)        { create(:agent, groups: [ticket.group]) }
  let(:ticket)       { create(:ticket) }
  let(:variables)    { { ticketId: gql.id(ticket), locale: agent.locale } }
  let(:mock_channel) { build_mock_channel }
  let(:subscription) do
    <<~SUBSCRIPTION
      subscription ticketAIAssistanceSummaryUpdates($ticketId: ID!, $locale: String!) {
        ticketAIAssistanceSummaryUpdates(ticketId: $ticketId, locale: $locale) {
          summary {
            problem
            conversationSummary
            openQuestions
            suggestions
          }
          reason
          fingerprintMd5
          error {
            message
            exception
          }
          relevantForCurrentUser
        }
      }
    SUBSCRIPTION
  end

  before do
    Setting.set('ai_assistance_ticket_summary', true)
    Setting.set('ai_provider', 'zammad_ai')

    gql.execute(subscription, variables: variables, context: { channel: mock_channel })
  end

  context 'when subscribed' do
    it 'subscribes' do
      expect(gql.result.data).to include('summary' => nil)
    end

    context 'when a summary job is executed' do
      let(:expected_summary) do
        {
          'problem'        => 'Houston we got a problem',
          'summary'        => 'short summary',
          'open_questions' => ['question 1', 'question 2'],
          'suggestions'    => ['do this and that'],
          'reason'         => 'example',
        }
      end

      let(:expected_result) do
        AI::Service::Result.new(
          content: expected_summary,
          fresh:   true
        )
      end

      let(:expected_broadcasted_summary) do
        {
          'problem'             => 'Houston we got a problem',
          'conversationSummary' => 'short summary',
          'openQuestions'       => ['question 1', 'question 2'],
          'suggestions'         => ['do this and that'],
        }
      end

      before do
        allow_any_instance_of(Service::Ticket::AIAssistance::Summarize)
          .to receive(:execute)
          .and_return(expected_result)
      end

      it 'receives new summary data' do
        TicketAIAssistanceSummarizeJob.new.perform(ticket, agent.locale)
        expect(mock_channel.mock_broadcasted_messages.first).to include(
          result: include(
            'data' => include(
              'ticketAIAssistanceSummaryUpdates' => include(
                'summary'                => expected_broadcasted_summary,
                'reason'                 => 'example',
                'fingerprintMd5'         => Digest::MD5.hexdigest(expected_summary.slice('problem', 'summary', 'open_questions', 'suggestions').to_s),
                'relevantForCurrentUser' => true,
              )
            )
          )
        )
      end

      context 'when the summary is relevant for the current user' do
        before do
          another_user = create(:agent, groups: [ticket.group])
          create(:ticket_article, :outbound_email, origin_by: another_user, ticket:, body: 'This is a test article')
        end

        it 'receives new summary data' do
          TicketAIAssistanceSummarizeJob.new.perform(ticket, agent.locale)
          expect(mock_channel.mock_broadcasted_messages.first).to include(
            result: include(
              'data' => include(
                'ticketAIAssistanceSummaryUpdates' => include(
                  'summary'                => expected_broadcasted_summary,
                  'reason'                 => 'example',
                  'fingerprintMd5'         => Digest::MD5.hexdigest(expected_summary.slice('problem', 'summary', 'open_questions', 'suggestions').to_s),
                  'relevantForCurrentUser' => true,
                )
              )
            )
          )
        end
      end

      context 'when the summary is not relevant for the current user' do
        before do
          create(:ticket_article, :outbound_email, origin_by: agent, ticket:, body: 'This is a test article')
        end

        it 'receives new summary data' do
          TicketAIAssistanceSummarizeJob.new.perform(ticket, agent.locale)
          expect(mock_channel.mock_broadcasted_messages.first).to include(
            result: include(
              'data' => include(
                'ticketAIAssistanceSummaryUpdates' => include(
                  'summary'                => expected_broadcasted_summary,
                  'reason'                 => 'example',
                  'fingerprintMd5'         => Digest::MD5.hexdigest(expected_summary.slice('problem', 'summary', 'open_questions', 'suggestions').to_s),
                  'relevantForCurrentUser' => false,
                )
              )
            )
          )
        end
      end
    end
  end
end
