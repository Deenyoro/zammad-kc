# KC: run in a Zammad test environment after copying kc/ into the app tree
# (kc/script/apply-overlay.sh, then cp -r kc/spec/. spec/):
#   bundle exec rspec spec/models/channel/driver/kc_microsoft_teams_chat_spec.rb

require 'rails_helper'

RSpec.describe Channel::Driver::KcMicrosoftTeamsChat do
  let(:driver) { described_class.new }

  describe '#graph_url?' do
    it 'accepts Microsoft Graph over https', :aggregate_failures do
      expect(driver.send(:graph_url?, 'https://graph.microsoft.com/v1.0/chats/x/messages/1')).to be(true)
      expect(driver.send(:graph_url?, 'https://GRAPH.microsoft.com/beta/x')).to be(true)
    end

    it 'rejects any other host or scheme', :aggregate_failures do
      expect(driver.send(:graph_url?, 'https://attacker.example/graph.microsoft.com')).to be(false)
      expect(driver.send(:graph_url?, 'https://graph.microsoft.com.attacker.example/x')).to be(false)
      expect(driver.send(:graph_url?, 'http://graph.microsoft.com/v1.0/x')).to be(false)
      expect(driver.send(:graph_url?, 'http://10.0.0.1/')).to be(false)
      expect(driver.send(:graph_url?, 'not a url')).to be(false)
    end
  end

  describe '#download_and_attach_files' do
    let(:graph)   { instance_double(Kc::MicrosoftTeamsGraph, access_token: 'token') }
    let(:ticket)  { create(:ticket) }
    let(:article) { create(:ticket_article, ticket: ticket, content_type: 'text/html', body: 'hi') }
    let(:channel) { Channel.new(area: 'MicrosoftTeamsChat::Account', options: {}) }

    before { allow(driver).to receive(:build_graph_client).and_return(graph) }

    it 'never sends the account token to a non-Graph contentUrl', :aggregate_failures do
      allow(UserAgent).to receive(:get)

      driver.send(:download_and_attach_files, article, channel, {
                    chat_id:      'chat', message_id: '1', body_content: 'hi',
                    attachments:  [{ id: 'a', name: 'x.png', contentType: 'image/png', contentUrl: 'https://attacker.example/x.png' }],
                  })

      expect(UserAgent).not_to have_received(:get)
      expect(article.reload.body).to include('https://attacker.example/x.png')
    end
  end

  describe '#process recipients' do
    let(:channel) do
      Channel.create!(area: 'MicrosoftTeamsChat::Account', group: Group.first, active: true,
                      options: { user_id: 'me', tenant_id: 't1' }, created_by_id: 1, updated_by_id: 1)
    end
    let(:members) do
      [{ 'userId' => 'me', 'displayName' => 'KawaConnect Support' },
       { 'userId' => 'u1', 'displayName' => 'Ann Lee' },
       { 'userId' => 'u2', 'displayName' => 'Bob Ray' }]
    end

    def message(id, chat_type:, topic: nil)
      { chat_id: '19:chat', message_id: id, from_user_id: 'u1', from_display_name: 'Ann Lee',
        from_email: 'ann@example.com', body_content: 'hello', body_content_type: 'text',
        created_at: Time.current.iso8601, tenant_id: 't1', chat_type: chat_type, chat_topic: topic,
        chat_members: members, attachments: [], hosted_contents: [] }
    end

    before do
      Ticket::Article::Type.lookup(name: 'teams_chat_message') || create(:ticket_article_type, name: 'teams_chat_message')
      allow(driver).to receive(:add_context_note)
      allow(driver).to receive(:download_and_attach_files)
    end

    it 'stores the chat audience and names the group chat as the recipient', :aggregate_failures do
      result = driver.process(channel.options, message('m1', chat_type: 'group', topic: 'Office move'), channel)

      audience = result[:ticket].reload.preferences.dig(:teams_chat, :audience)
      expect(audience.to_h.with_indifferent_access).to include(chat_type: 'group', members: ['Ann Lee', 'Bob Ray'])
      expect(result[:article].to).to eq('Group chat "Office move" (Ann Lee, Bob Ray)')
    end

    it 'names our account as the recipient of a one-on-one message' do
      members.pop
      result = driver.process(channel.options, message('m2', chat_type: 'oneOnOne'), channel)

      expect(result[:article].to).to eq('KawaConnect Support')
    end
  end
end
