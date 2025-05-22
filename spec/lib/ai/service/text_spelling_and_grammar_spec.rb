# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe AI::Service::TextSpellingAndGrammar, required_envs: %w[OPEN_AI_TOKEN ZAMMAD_AI_TOKEN ZAMMAD_AI_API_URL], use_vcr: true do
  subject(:ai_service) { described_class.new(current_user:, context_data:) }

  let(:context_data)   { { input: 'I Nicole Braun.' } }
  let(:current_user)   { create(:user) }

  context 'when service is executed with OpenAI as provider' do
    before do
      Setting.set('ai_provider', 'open_ai')
      Setting.set('ai_provider_config', {
                    token: ENV['OPEN_AI_TOKEN'],
                  })
    end

    it 'check that grammar is correct' do
      result = ai_service.execute
      expect(result).to include('I am Nicole Braun.')
    end
  end

  context 'when service is executed with ZammadAI as provider' do
    before do
      Setting.set('ai_provider', 'zammad_ai')
      Setting.set('ai_provider_config', {
                    token: ENV['ZAMMAD_AI_TOKEN'],
                  })
    end

    it 'check that grammar is correct' do
      result = ai_service.execute
      expect(result.content).to include('I am Nicole Braun.')
    end
  end
end
