# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe HttpLog, :aggregate_failures do
  subject(:http_log) { build(:http_log) }

  describe 'callbacks' do
    # See https://github.com/zammad/zammad/issues/2100
    it 'converts request/response message data to UTF-8 before saving' do
      http_log.request[:content]  = 'foo'.dup.force_encoding('ascii-8bit')
      http_log.response[:content] = 'bar'.dup.force_encoding('ascii-8bit')

      expect { http_log.save }
        .to change { http_log.request[:content].encoding.name }.from('ASCII-8BIT').to('UTF-8')
        .and change { http_log.response[:content].encoding.name }.from('ASCII-8BIT').to('UTF-8')
    end
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(http_log).to be_valid
    end

    it 'is invalid with unknown facility' do
      http_log.facility = 'unknown'
      expect(http_log).not_to be_valid
      expect(http_log.errors[:facility]).to include('is not included in the list')
    end
  end

  describe '.facility_to_permission' do
    it 'returns correct permission for known facility' do
      expect(described_class.facility_to_permission('GitHub')).to eq('admin.integration')
      expect(described_class.facility_to_permission('webhook')).to eq('admin.webhook')
      expect(described_class.facility_to_permission('cti')).to eq('admin.integration')
      expect(described_class.facility_to_permission('AI::Provider')).to eq('admin.ai_provider')
      expect(described_class.facility_to_permission('WhatsApp::Business')).to eq('admin.channel_whatsapp')
    end

    it 'returns admin.* for blank facility' do
      expect(described_class.facility_to_permission(nil)).to eq('admin.*')
      expect(described_class.facility_to_permission('')).to eq('admin.*')
    end

    it 'returns nil for unknown facility' do
      expect(described_class.facility_to_permission('unknown')).to be_nil
    end
  end

  describe '.facilities_by_permission' do
    it 'returns a hash grouped by permissions with facilities' do
      expect(described_class.facilities_by_permission).to include(
        'admin.ai_provider'      => include('AI::Provider'),
        'admin.integration'      => include('GitHub'),
        'admin.security'         => include('SAML'),
        'admin.webhook'          => include('webhook'),
        'admin.channel_whatsapp' => include('WhatsApp::Business')
      )
    end
  end
end
