# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe AI::Service, required_envs: %w[OPEN_AI_TOKEN], use_vcr: true do
  subject(:ai_service) { AI::Service::TicketSummarize.new(current_user:, context_data:) }

  let(:ticket_article) { create(:ticket_article) }
  let(:context_data)   { { ticket: ticket_article.ticket } }
  let(:current_user)   { create(:user) }

  before do
    stub_request(:get, 'https://api.openai.com/v1/models').to_return(
      status:  200,
      body:    '{"data": [{"id": "gpt-3.5-turbo"}]}',
      headers: { 'Content-Type' => 'application/json' }
    )

    Setting.set('ai_provider', 'open_ai')
    Setting.set('ai_provider_config', {
                  token: ENV['OPEN_AI_TOKEN'],
                })
  end

  context 'when service is executed' do
    it 'check result' do
      result = ai_service.execute
      expect(result).not_to be_nil
    end

    context 'when AI response is a empty string' do
      let(:provider_double) { instance_double(AI::Provider::OpenAI, ask: '', metadata: { provider: 'AI::Provider::OpenAI' }) }

      before do
        allow(AI::Provider::OpenAI).to receive(:new).and_return(provider_double)
      end

      it 'returns a result' do
        result = ai_service.execute
        expect(result).not_to be_nil
      end
    end
  end
end
