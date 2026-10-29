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

  it 'uses the channel group when no group is given', :aggregate_failures do
    expect do
      post '/api/v1/kc/conversations/sms',
           params: { channel_id: channel.id, phone_number: '+15555550111', body: 'hi', group_id: '', skip_send: true },
           as:     :json
    end.to change(Ticket, :count).by(1)
    expect(Ticket.last.group_id).to eq(group_ok.id)
  end

  it 'lists only the active groups the agent may create tickets in', :aggregate_failures do
    inactive = create(:group, active: false)
    agent.group_names_access_map = {
      group_ok.name     => %w[read change create],
      group_denied.name => %w[read change],
      inactive.name     => %w[full],
    }

    get '/api/v1/kc/conversations/groups', as: :json

    expect(response).to have_http_status(:ok)
    expect(json_response['groups'].pluck('id')).to eq([group_ok.id])
  end

  describe 'GET /api/v1/kc/conversations/draft_state' do
    let(:state) { { 'phone_number' => '+15555550111', 'body' => 'Draft text', 'skip_send' => false } }

    def draft(user:, key: 'KcNewSmsScreen-42', app: 'desktop', callback: 'KcNewSmsConversationContent')
      create(:taskbar, user_id: user.id, app: app, key: key, callback: callback, params: { id: '42' }, state: state)
    end

    it 'returns the stored form of an own draft', :aggregate_failures do
      draft(user: agent)

      get '/api/v1/kc/conversations/draft_state', params: { key: 'KcNewSmsScreen-42' }

      expect(response).to have_http_status(:ok)
      expect(json_response).to eq('exists' => true, 'state' => state)
    end

    it 'answers an empty state for a draft that has not been stored yet' do
      get '/api/v1/kc/conversations/draft_state', params: { key: 'KcNewTeamsScreen-1' }

      expect(json_response).to eq('exists' => false, 'state' => {})
    end

    it 'never returns the draft of another user' do
      draft(user: create(:agent))

      get '/api/v1/kc/conversations/draft_state', params: { key: 'KcNewSmsScreen-42' }

      expect(json_response).to eq('exists' => false, 'state' => {})
    end

    it 'refuses keys of other tasks', :aggregate_failures do
      draft(user: agent, key: 'TicketCreateScreen-42', callback: 'TicketCreate')

      get '/api/v1/kc/conversations/draft_state', params: { key: 'TicketCreateScreen-42' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response).not_to have_key('state')
    end
  end
end
