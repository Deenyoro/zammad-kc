# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Service::AIAssistance::TextTools do
  subject(:service) { described_class.new(input:, service_type:) }

  context 'when text tool service is used' do
    before do
      Setting.set('ai_provider', 'open_ai')
      Setting.set('ai_assistance_text_tools', true)

      allow_any_instance_of(AI::Service::TextSpellingAndGrammar)
        .to receive(:execute)
        .and_return(expected_output)
    end

    let(:input)           { 'Hello, wrld!' }
    let(:expected_output) { 'Hello, world!' }

    describe '#execute' do
      context 'when correct service type is used' do
        let(:service_type) { 'spelling_and_grammar' }

        it 'returns the corrected input' do
          expect(service.execute).to eq(expected_output)
        end
      end

      context 'when not existing service type is used' do
        let(:service_type) { 'not_existing' }

        it 'raises an error' do
          expect { service.execute }.to raise_error(ArgumentError, "AI assistance text tool service type 'not_existing' is not supported.")
        end
      end
    end
  end
end
