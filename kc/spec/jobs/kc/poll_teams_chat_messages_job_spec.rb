# KC: run in a Zammad test environment after copying kc/ into the app tree
# (kc/script/apply-overlay.sh, then cp -r kc/spec/. spec/):
#   bundle exec rspec spec/jobs/kc/poll_teams_chat_messages_job_spec.rb

require 'rails_helper'

RSpec.describe Kc::PollTeamsChatMessagesJob do
  let(:tenant_a) { 'aaaaaaaa-0000-0000-0000-000000000001' }
  let(:tenant_b) { 'bbbbbbbb-0000-0000-0000-000000000002' }

  describe '.same_tenant?' do
    it 'matches the channel tenant, case-insensitively' do
      expect(described_class.same_tenant?({ 'tenant_id' => tenant_a.upcase }, tenant_a)).to be(true)
    end

    it 'rejects a chat from another tenant' do
      expect(described_class.same_tenant?({ 'tenant_id' => tenant_b }, tenant_a)).to be(false)
    end

    it 'keeps tickets without a recorded tenant' do
      expect(described_class.same_tenant?({}, tenant_a)).to be(true)
    end
  end

  describe '#active_chat_ids_for' do
    let(:channel_a) { create(:channel, area: 'MicrosoftTeamsChat::Account', active: true, options: { tenant_id: tenant_a }) }
    let(:channel_b) { create(:channel, area: 'MicrosoftTeamsChat::Account', active: true, options: { tenant_id: tenant_b }) }

    before do
      create(:ticket, state_name: 'open', preferences: { teams_chat: { chat_id: 'chat-a', tenant_id: tenant_a } })
      create(:ticket, state_name: 'open', preferences: { teams_chat: { chat_id: 'chat-b', tenant_id: tenant_b } })
      create(:ticket, state_name: 'open', preferences: { teams_chat: { chat_id: 'chat-legacy' } })
      create(:ticket, state_name: 'closed', preferences: { teams_chat: { chat_id: 'chat-closed', tenant_id: tenant_a } })
    end

    it 'polls only open chats of the channel tenant (plus tenant-less legacy chats)', :aggregate_failures do
      job = described_class.new
      expect(job.send(:active_chat_ids_for, channel_a)).to contain_exactly('chat-a', 'chat-legacy')
      expect(job.send(:active_chat_ids_for, channel_b)).to contain_exactly('chat-b', 'chat-legacy')
    end
  end
end
