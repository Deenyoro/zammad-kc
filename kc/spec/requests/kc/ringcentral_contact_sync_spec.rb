# KC: run in a Zammad test environment after copying kc/ into the app tree
# (kc/script/apply-overlay.sh, then cp -r kc/spec/. spec/):
#   bundle exec rspec spec/requests/kc/ringcentral_contact_sync_spec.rb

require 'rails_helper'

RSpec.describe 'KC RingCentral contact sync admin endpoints', type: :request do
  let(:admin)   { create(:admin) }
  let(:agent)   { create(:agent) }
  let(:channel) { create(:channel, area: 'RingCentralSms::Account', options: { phone_number: '+14125550000', contact_import: false, contact_export: false }) }

  describe 'PUT /api/v1/kc/ringcentral_sms_channels/:id' do
    before { authenticated_as(admin) }

    it 'turns the switches on and off from the edit form', :aggregate_failures do
      put "/api/v1/kc/ringcentral_sms_channels/#{channel.id}", params: { contact_sync_form: '1', contact_import: 'true', contact_export: 'true' }, as: :json
      expect(response).to have_http_status(:ok)
      expect(channel.reload.options).to include('contact_import' => true, 'contact_export' => true)

      put "/api/v1/kc/ringcentral_sms_channels/#{channel.id}", params: { contact_sync_form: '1', contact_import: 'true' }, as: :json
      expect(channel.reload.options).to include('contact_import' => true, 'contact_export' => false)
    end

    it 'leaves the switches alone for other updates' do
      channel.options[:contact_export] = true
      channel.save!
      put "/api/v1/kc/ringcentral_sms_channels/#{channel.id}", params: { thread_window_hours: 12 }, as: :json
      expect(channel.reload.options).to include('contact_export' => true)
    end
  end

  describe 'POST /api/v1/kc/ringcentral_sms_channels/:id/sync_contacts' do
    it 'refuses agents' do
      authenticated_as(agent)
      post "/api/v1/kc/ringcentral_sms_channels/#{channel.id}/sync_contacts", as: :json
      expect(response).to have_http_status(:forbidden)
    end

    context 'with an admin' do
      before { authenticated_as(admin) }

      it 'asks to turn a direction on first' do
        post "/api/v1/kc/ringcentral_sms_channels/#{channel.id}/sync_contacts", as: :json
        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'queues the sync for the channel', performs_jobs: true do
        channel.options[:contact_import] = true
        channel.save!

        expect { post "/api/v1/kc/ringcentral_sms_channels/#{channel.id}/sync_contacts", as: :json }
          .to have_enqueued_job(Kc::RingcentralContactSyncJob).with(channel.id)
      end
    end
  end
end
