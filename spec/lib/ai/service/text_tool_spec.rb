# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe AI::Service::TextTool, required_envs: %w[OPEN_AI_TOKEN ZAMMAD_AI_TOKEN ZAMMAD_AI_API_URL], use_vcr: true do
  subject(:ai_service) { described_class.new(current_user:, context_data:) }

  let(:current_user) { create(:user) }

  let(:context_data) do
    {
      instruction:        'You task is to proofread the provided input text to correct any spelling and grammatical mistakes to ensure professionalism and clarity, while preserving all existing HTML markup without alteration.

- Correct all typos, misspellings, and errors in sentence structure, punctuation, and verb conjugation.
- Maintain the language of the given input text for the output.
- Do not modify or break any HTML tags or markup present in the input text.

Carefully review the text to improve readability and correctness without altering its original formatting or markup.',
      fixed_instructions: Setting.get('ai_assistance_text_tools_fixed_instructions'),
      input:              'I ma Nicole Braun.',
    }
  end

  context 'when service is executed with OpenAI as provider' do
    before do
      Setting.set('ai_provider', 'open_ai')
      Setting.set('ai_provider_config', {
                    token: ENV['OPEN_AI_TOKEN'],
                  })
    end

    it 'check that grammar is correct' do
      result = ai_service.execute
      expect(result.content).to include('I am Nicole Braun.')
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
