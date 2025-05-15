# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'AI Assistance API endpoints', authenticated_as: :user, type: :request do
  let(:user)   { create(:agent) }
  let(:input)  { Faker::Lorem.unique.sentence }
  let(:output) { Faker::Lorem.unique.paragraph }

  describe '#text_tools' do
    let(:params) do
      {
        input:,
        service_type:,
      }
    end

    before do
      Setting.set('ai_provider', 'zammad_ai')
      Setting.set('ai_assistance_text_tools', true)
    end

    context 'when using text improvement service' do
      let(:service_type) { 'improve_writing' }

      before do
        allow_any_instance_of(AI::Service::TextImproveWriting)
          .to receive(:execute)
          .and_return(output)

        post '/api/v1/ai_assistance/text_tools', params:, as: :json
      end

      context 'when user has agent access' do
        it 'returns improved text' do
          expect(json_response).to eq({ 'output' => output })
        end
      end

      context 'when user does not have agent access' do
        let(:user) { create(:customer) }

        it 'raises error' do
          expect(response).to have_http_status(:forbidden)
        end
      end
    end
  end
end
