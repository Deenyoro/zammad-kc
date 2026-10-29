# KC: run in a Zammad test environment after copying kc/ into the app tree
# (kc/script/apply-overlay.sh, then cp -r kc/spec/. spec/):
#   bundle exec rspec spec/requests/kc/new_conversations_spec.rb

require 'rails_helper'

RSpec.describe 'KC new conversations', type: :request do
  let(:group_ok)     { create(:group) }
  let(:group_denied) { create(:group) }
  let(:agent) do
    user = create(:agent)
    user.group_names_access_map = {
      group_ok.name     => %w[read change create],
      group_denied.name => %w[read change],
    }
    user
  end
  let(:channel) do
    create(:channel, area: 'RingCentralSms::Account', active: true, group: group_ok,
                     options: { phone_number: '+15555550100' })
  end

  before do
    channel
    authenticated_as(agent)
  end

  it 'refuses a group the agent cannot create tickets in', :aggregate_failures do
    expect do
      post '/api/v1/kc/conversations/sms',
           params: { channel_id: channel.id, phone_number: '+15555550111', body: 'hi', group_id: group_denied.id, skip_send: true },
           as:     :json
    end.not_to change(Ticket, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it 'creates the ticket in a group the agent may create in', :aggregate_failures do
    expect do
      post '/api/v1/kc/conversations/sms',
           params: { channel_id: channel.id, phone_number: '+15555550111', body: 'hi', group_id: group_ok.id, skip_send: true },
           as:     :json
    end.to change(Ticket, :count).by(1)
    expect(Ticket.last.group_id).to eq(group_ok.id)
  end
end
