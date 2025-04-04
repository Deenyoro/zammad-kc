# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'AI > Provider', authenticated_as: :admin, type: :system do
  let(:admin) { create(:admin) }

  before do
    setting = Setting.find_by(name: 'ai_provider_config')
    setting.update!(preferences: {})

    result = UserAgent::Result.new(
      success: true,
      code:    200,
    )

    allow(UserAgent).to receive_messages(get: result, post: result)

    visit '/#ai/provider'
  end

  it 'allows configuring AI provider settings' do
    within :active_content do
      expect(page).to have_text('Provider')
      expect(page).to have_text('This service allows you to connect Zammad with an AI provider.')

      find('select[name=provider]').select('OpenAI')

      fill_in 'token', with: '1234111'

      click '.js-provider-submit'

      await_empty_ajax_queue

      # Verify settings were saved
      expect(Setting.get('ai_provider')).to eq('open_ai')
      expect(Setting.get('ai_provider_config')).to eq({ 'token' => '1234111' })
    end
  end

  it 'shows a field for selecting a provider' do
    within :active_content do
      find('select[name=provider]').select('OpenAI')
      expect(page).to have_field('Token')

      find('select[name=provider]').select('Ollama')
      expect(page).to have_field('URL')
    end
  end

  it 'validates required fields' do
    within :active_content do
      find('select[name=provider]').select('OpenAI')

      click '.js-provider-submit'

      expect(page).to have_text('is required')
    end
  end
end
