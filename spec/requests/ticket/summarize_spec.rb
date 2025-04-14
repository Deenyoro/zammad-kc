# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'Ticket Summarize API endpoints', authenticated_as: :user, performs_jobs: true, type: :request do
  let(:user)   { create(:agent) }
  let(:ticket) { create(:ticket) }

  before do
    Setting.set('ai_provider', 'zammad_ai')
    Setting.set('ai_assistance_ticket_summary', true)
  end

  describe '#enqueue' do
    def make_request
      post "/api/v1/tickets/#{ticket.id}/enqueue_summarize", as: :json
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
            'problem'        => 'mocked problem',
            'summary'        => 'mocked conversation_summary',
            'open_questions' => 'mocked open_questions',
            'suggestions'    => 'mocked suggestions',
          }
        end

        before { allow(Rails.cache).to receive(:read).and_return(result) }

        it 'returns cached version' do
          make_request

          expect(json_response).to eq({ 'result' => {
                                        'conversation_summary' => 'mocked conversation_summary',
                                        'open_questions'       => 'mocked open_questions',
                                        'suggestions'          => 'mocked suggestions',
                                        'problem'              => 'mocked problem',
                                        'fingerprint_md5'      => Digest::MD5.hexdigest(result.slice('problem', 'summary', 'open_questions', 'suggestions').to_s),
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
