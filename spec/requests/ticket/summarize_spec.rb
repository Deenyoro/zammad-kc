# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'Ticket Summarize API endpoints', authenticated_as: :user, performs_jobs: true, type: :request do
  let(:user)                         { create(:agent) }
  let(:ticket)                       { article.ticket }
  let(:article)                      { create(:ticket_article) }
  let(:ai_assistance_ticket_summary) { true }

  before do
    allow(AI::Provider::ZammadAI).to receive(:ping!).and_return(true)

    Setting.set('ai_provider', 'zammad_ai')
    Setting.set('ai_assistance_ticket_summary', ai_assistance_ticket_summary)
  end

  describe '#summarize' do
    def make_request
      post "/api/v1/tickets/#{ticket.id}/summarize", as: :json
    end

    context 'when feature is disabled' do
      let(:ai_assistance_ticket_summary) { false }

      it 'raises error', :aggregate_failures do
        make_request

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['error']).to eq('This feature is not enabled.')
      end
    end

    context 'when user does not have agent access' do
      it 'raises error' do
        make_request
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when user has agent access' do
      before { user.groups << ticket.group }

      context 'when cache is present' do
        let(:result) do
          {
            'customer_request'     => 'mocked customer_request',
            'conversation_summary' => 'mocked conversation_summary',
            'open_questions'       => ['mocked open_questions'],
            'upcoming_events'      => ['mocked upcoming_events'],
            'customer_mood'        => 'mocked customer_mood',
            'customer_emotion'     => 'mocked customer_emotion',
          }
        end

        before do
          AI::StoredResult.create!(
            content: result,
            version: AI::Service::TicketSummarize.persistent_version({ ticket: }, Locale.find_by(locale: user.locale)),
            **AI::Service::TicketSummarize.persistent_lookup_attributes({ ticket: }, Locale.find_by(locale: user.locale)),
          )
        end

        it 'returns cached version' do
          make_request

          expect(json_response).to eq({ 'result' => {
                                        'customer_request'          => 'mocked customer_request',
                                        'conversation_summary'      => 'mocked conversation_summary',
                                        'open_questions'            => ['mocked open_questions'],
                                        'upcoming_events'           => ['mocked upcoming_events'],
                                        'customer_mood'             => 'mocked customer_mood',
                                        'customer_emotion'          => 'mocked customer_emotion',
                                        'fingerprint_md5'           => Digest::MD5.hexdigest(result.sort.to_h.to_s),
                                        'relevant_for_current_user' => true,
                                      } })
        end

        it 'does not enqueue summary generation job' do
          make_request

          expect(TicketAIAssistanceSummarizeJob).not_to have_been_enqueued
        end
      end

      context 'when cache is not present' do
        it 'enqueues summary generation job' do
          make_request

          expect(TicketAIAssistanceSummarizeJob).to have_been_enqueued.with(ticket, user.locale)
        end

        it 'returns empty result' do
          make_request

          expect(json_response).to eq({ 'result' => nil })
        end
      end
    end
  end
end
