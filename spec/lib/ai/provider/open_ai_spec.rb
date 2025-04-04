# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe AI::Provider::OpenAI, required_envs: %w[OPEN_AI_TOKEN], use_vcr: true do
  subject(:ai_provider) do
    described_class.new(
      prompt_system: '',
      prompt_user:   'This is a connection test. Return "true" in unprettified json if you got the message.',
    )
  end

  before do
    Setting.set('ai_provider', 'open_ai')
    Setting.set('ai_provider_config', {
                  token: ENV['OPEN_AI_TOKEN'],
                })
  end

  it 'does exchange data with open ai endpoint' do
    expect(ai_provider.request).to include('true')
  end

  context 'when API is faulty' do
    it 'raises an error' do
      allow(UserAgent).to receive(:post).and_return(
        UserAgent::Result.new(
          error:   '',
          success: false,
          code:    400,
        )
      )

      expect { ai_provider.request }.to raise_error(AI::Provider::ResponseError, 'Invalid request - please check your input')
    end
  end
end
