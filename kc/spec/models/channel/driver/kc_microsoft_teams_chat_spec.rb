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
end
