# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'
require 'models/core_workflow/base'

RSpec.describe CoreWorkflow::Custom::AdminGroupSummaryGeneration, type: :model do
  include_context 'with core workflow base'

  let(:payload) do
    base_payload.merge(
      'class_name' => 'Group',
    )
  end

  context 'when settings enabled' do
    before do
      Setting.set('ai_provider', 'zammad_ai')
    end

    it 'does show ticket generation field for group' do
      expect(result[:visibility]['summary_generation']).to eq('show')
    end
  end

  context 'when settings disabled' do
    before do
      Setting.set('ai_provider', '')
    end

    it 'does not show ticket generation field for group' do
      expect(result[:visibility]['summary_generation']).to eq('remove')
    end
  end
end
