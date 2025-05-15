# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

# TODO: Add AZURE_URL_EMBEDDINGS when needed.
RSpec.describe AI::Provider::Azure, required_envs: %w[AZURE_TOKEN AZURE_URL_COMPLETIONS AZURE_HOST], use_vcr: true do
  subject(:ai_provider) { described_class.new(options: { json_response: true }) }

  let(:prompt_system) { '' }
  let(:prompt_user)   { 'This is a connection test. Return in unprettified JSON \'{ "connected": "true" }\' if you got the message.' }

  before do
    Setting.set('ai_provider', 'azure')
    Setting.set('ai_provider_config', {
                  token:           ENV['AZURE_TOKEN'],
                  url_completions: ENV['AZURE_URL_COMPLETIONS'],

                  # TODO: Enable it when needed.
                  # url_embeddings:  ENV['AZURE_URL_EMBEDDINGS']
                })
  end

  it 'does exchange data with azure ai endpoint' do
    expect(ai_provider.ask(prompt_system:, prompt_user:)).to match({ 'connected' => 'true' })
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

      expect do
        ai_provider.ask(prompt_system:, prompt_user:)
      end.to raise_error(AI::Provider::ResponseError, 'Invalid request - please check your input')
    end
  end
end
