# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe AI::Service::TextTool, required_envs: %w[OPEN_AI_TOKEN ZAMMAD_AI_TOKEN], use_vcr: true do
  subject(:ai_service) { described_class.new(current_user:, context_data:) }

  let(:current_user) { create(:user) }
  let(:text_tool)    { create(:ai_text_tool) }

  let(:context_data) do
    {
      instruction:        'You are a text correction AI assistant.

You are given a text, most likely in HTML format.

Your task is to correct:
- spelling
- grammar
- punctuation
- and sentence-structure errors.

You have to follow these rules:
- Detect the input language and make sure the corrected text is using the same language.
- Correct only the text content, neither the HTML tags nor the given structure.
- Preserve all HTML tags and formatting exactly as in the input.',
      fixed_instructions: Setting.get('ai_assistance_text_tools_fixed_instructions'),
      input:              'I ma Nicole Braun.',
      text_tool:,
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
