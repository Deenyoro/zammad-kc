# KC: run in a Zammad test environment after copying kc/ into the app tree
# (kc/script/apply-overlay.sh, then cp -r kc/spec/. spec/):
#   bundle exec rspec spec/services/kc/article_recipients_spec.rb

require 'rails_helper'

RSpec.describe Kc::ArticleRecipients do
  let(:agent_sender)    { Ticket::Article::Sender.lookup(name: 'Agent') }
  let(:customer_sender) { Ticket::Article::Sender.lookup(name: 'Customer') }

  def type_id(name)
    Ticket::Article::Type.lookup(name: name)&.id || create(:ticket_article_type, name: name).id
  end

  before do
    allow(Kc::PhoneContacts).to receive_messages(ringcentral_book: {}, freepbx_book: {})
    create(:customer, firstname: 'Jane', lastname: 'Smith', mobile: '+14125550100')
  end

  describe 'RingCentral SMS' do
    let(:ticket) do
      create(:ticket, preferences: { ringcentral_sms: {
               from_phone: '+14125550100', to_phone: '+14125559999',
               participants: %w[+14125550100 +14125550111], channel_id: 1,
             } })
    end

    it 'names every participant of an agent reply, whatever the form sent', :aggregate_failures do
      article = create(:ticket_article, ticket: ticket, type_id: type_id('ringcentral_sms_message'),
                       sender_id: agent_sender.id, to: '+14125550100', body: 'hi')
      expect(article.to).to eq('Jane Smith (+14125550100), +14125550111')
    end

    it 'prefers the recipients stored on the article' do
      article = create(:ticket_article, ticket: ticket, type_id: type_id('ringcentral_sms_message'),
                       sender_id: agent_sender.id, body: 'hi',
                       preferences: { ringcentral_sms: { to_phones: ['+14125550100'] } })
      expect(article.to).to eq('Jane Smith (+14125550100)')
    end

    it 'shows our number on an inbound text' do
      article = create(:ticket_article, ticket: ticket, type_id: type_id('ringcentral_sms_message'),
                       sender_id: customer_sender.id, from: 'Jane Smith (+14125550100)', body: 'hello',
                       preferences: { ringcentral_sms: { from_phone: '+14125550100', to_phone: '+14125559999' } })
      expect(article.to).to eq('+14125559999')
    end
  end

  describe 'FreePBX SMS' do
    let(:ticket) { create(:ticket, preferences: { freepbx_sms: { from_phone: '+14125550100', to_phone: '+14125559999' } }) }

    it 'falls back to the customer number for an agent reply' do
      article = create(:ticket_article, ticket: ticket, type_id: type_id('freepbx_sms_message'),
                       sender_id: agent_sender.id, body: 'hi')
      expect(article.to).to eq('Jane Smith (+14125550100)')
    end
  end

  describe 'Teams' do
    let(:customer) { create(:customer, firstname: 'Ann', lastname: 'Lee') }
    let(:audience) { nil }
    let(:ticket) do
      prefs = { chat_id: '19:abc', channel_id: 1 }
      prefs[:audience] = audience if audience
      create(:ticket, customer: customer, preferences: { teams_chat: prefs })
    end

    context 'with a one-on-one chat' do
      let(:audience) { { chat_type: 'oneOnOne', members: ['Ann Lee'], account_name: 'KawaConnect Support' } }

      it 'names the other person on an agent reply' do
        article = create(:ticket_article, ticket: ticket, type_id: type_id('teams_chat_message'),
                         sender_id: agent_sender.id, to: '', body: 'hi')
        expect(article.to).to eq('Ann Lee')
      end

      it 'names our account on an inbound message' do
        article = create(:ticket_article, ticket: ticket, type_id: type_id('teams_chat_message'),
                         sender_id: customer_sender.id, from: 'Ann Lee', body: 'hello')
        expect(article.to).to eq('KawaConnect Support')
      end
    end

    context 'with a group chat' do
      let(:audience) { { chat_type: 'group', topic: 'Office move', members: ['Ann Lee', 'Bob Ray'] } }

      it 'names the chat and its members' do
        article = create(:ticket_article, ticket: ticket, type_id: type_id('teams_chat_message'),
                         sender_id: agent_sender.id, body: 'hi')
        expect(article.to).to eq('Group chat "Office move" (Ann Lee, Bob Ray)')
      end

      it 'labels Teams captures (internal notes) too' do
        article = create(:ticket_article, ticket: ticket, type_id: type_id('note'), internal: true,
                         sender_id: agent_sender.id, to: nil, body: 'sent in Teams',
                         preferences: { teams_chat: { outbound_capture: true } })
        expect(article.to).to eq('Group chat "Office move" (Ann Lee, Bob Ray)')
      end
    end

    context 'with a chat the driver has not described yet' do
      it 'keeps the recipient the form named' do
        article = create(:ticket_article, ticket: ticket, type_id: type_id('teams_chat_message'),
                         sender_id: agent_sender.id, to: 'Ann L.', body: 'hi')
        expect(article.to).to eq('Ann L.')
      end

      it 'falls back to the customer' do
        article = create(:ticket_article, ticket: ticket, type_id: type_id('teams_chat_message'),
                         sender_id: agent_sender.id, to: '', body: 'hi')
        expect(article.to).to eq('Ann Lee')
      end
    end
  end

  describe 'missed calls' do
    it 'names the dialed number when the note has no recipient' do
      ticket  = create(:ticket)
      article = create(:ticket_article, ticket: ticket, type_id: type_id('note'), sender_id: customer_sender.id,
                       from: '+14125550100', to: nil, subject: 'Missed Call', body: 'Missed call',
                       preferences: { ringcentral_missed_call: { from_phone: '+14125550100', to_phone: '+14125559999' } })
      expect(article.to).to eq('+14125559999')
    end
  end

  describe 'email' do
    it 'leaves email recipients alone' do
      article = create(:ticket_article, :outbound_email, to: 'a@example.com', cc: 'b@example.com')
      expect(article.reload).to have_attributes(to: 'a@example.com', cc: 'b@example.com')
    end
  end

  describe '.group_label' do
    it 'drops a topic Teams built from member names and caps the list', :aggregate_failures do
      names = (1..8).map { |i| "Person #{i}" }
      expect(described_class.group_label('A, B, C', names))
        .to eq('Group chat (Person 1, Person 2, Person 3, Person 4, Person 5, Person 6, +2 more)')
      expect(described_class.group_label(nil, [])).to eq('Group chat')
    end
  end

  describe '.audience_for' do
    it 'separates our connected account from the other members' do
      members = [{ 'userId' => 'me', 'displayName' => 'KawaConnect Support' },
                 { 'userId' => 'u1', 'displayName' => 'Ann Lee' }]
      expect(described_class.audience_for(chat_type: 'oneOnOne', topic: nil, members: members, account_user_id: 'me'))
        .to eq(chat_type: 'oneOnOne', members: ['Ann Lee'], account_name: 'KawaConnect Support')
    end
  end
end
