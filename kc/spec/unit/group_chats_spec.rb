# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Group conversations on RingCentral SMS and Microsoft Teams (KC 0.0.17).
# Standalone: ruby -S rspec --options /dev/null kc/spec/unit/group_chats_spec.rb

require 'rspec'
require 'active_support/all'

Time.zone = 'UTC'

module Kc; end
class Setting
  def self.get(_name) = nil
end
class Channel
  module Driver; end
end
class Ticket
  class Article; end
end

root = File.expand_path('../../..', __dir__)
require File.join(root, 'kc/lib/kc/sms_ticket_blocklist')
require File.join(root, 'kc/lib/kc/ringcentral_api')
require File.join(root, 'kc/lib/kc/teams_chat_title')
require File.join(root, 'kc/app/models/channel/driver/kc_ringcentral_sms')
require File.join(root, 'kc/app/models/channel/driver/kc_freepbx')

OURS  = '+14126097936'.freeze
ANN   = '+14125550101'.freeze
BOB   = '+14125550102'.freeze
CARL  = '+14125550103'.freeze

RSpec.describe Kc::RingcentralApi do
  describe '.conversation_key_candidates' do
    it 'keeps the our:other pair for a 1:1 text' do
      expect(described_class.conversation_key_candidates(OURS, [ANN])).to eq([described_class.conversation_key(OURS, ANN)])
    end

    it 'matches a group text only on the full participant set, never a member pair', :aggregate_failures do
      candidates = described_class.conversation_key_candidates(OURS, [BOB, ANN])
      expect(candidates).to eq([described_class.conversation_key(OURS, ANN, BOB)])
      expect(candidates).not_to include(described_class.conversation_key(OURS, ANN))
      expect(candidates).not_to include(described_class.conversation_key(OURS, BOB))
    end

    it 'gives the same key whatever order RingCentral lists the members in' do
      expect(described_class.conversation_key_candidates(OURS, [ANN, BOB, CARL]))
        .to eq(described_class.conversation_key_candidates(OURS, [CARL, ANN, BOB]))
    end

    it 'drops our own number from the members' do
      expect(described_class.conversation_key_candidates(OURS, [OURS, ANN])).to eq([described_class.conversation_key(OURS, ANN)])
    end
  end

  describe '.textable_number?' do
    it 'rejects company extension numbers', :aggregate_failures do
      expect(described_class.textable_number?('27')).to be(false)
      expect(described_class.textable_number?('+27')).to be(false)
      expect(described_class.textable_number?('4125550101')).to be(true)
      expect(described_class.textable_number?('+442079460100')).to be(true)
    end
  end
end

RSpec.describe Channel::Driver::KcRingcentralSms do
  subject(:driver) { described_class.new }

  describe 'recipients of a group text' do
    it 'ignores extension-only recipients so replies do not go to "+27"' do
      list = driver.send(:recipient_list, { to_phones: [OURS, '27', ANN] })
      expect(list).to eq([OURS, ANN])
    end

    it 'lists everyone but us as the other participants' do
      expect(driver.send(:other_participants, ANN, [OURS, BOB, CARL], OURS)).to eq([ANN, BOB, CARL])
    end
  end

  describe 'conversation candidates through the driver' do
    it 'keeps 1:1 and group conversations apart' do
      expect(driver.send(:conversation_key_candidates, OURS, [ANN, BOB]))
        .to eq(["#{OURS}:#{ANN}:#{BOB}".split(':').sort.join(':')])
    end
  end

  describe '.group_ticket_title' do
    it 'names every member', :aggregate_failures do
      expect(described_class.group_ticket_title(['Ann Lee', 'Bob Ray', CARL])).to eq("Group SMS: Ann Lee, Bob Ray, #{CARL}")
    end

    it 'caps the list and stays within 100 characters', :aggregate_failures do
      names = (1..7).map { |i| "Person Number #{i}" }
      title = described_class.group_ticket_title(names)
      expect(title).to start_with('Group SMS: Person Number 1, Person Number 2, Person Number 3, Person Number 4, +3 more')
      expect(title.length).to be <= 100
    end

    it 'uses a configured template' do
      allow(Setting).to receive(:get).with('kc_ringcentral_sms_group_ticket_title_template').and_return('Group text with {participants}')
      expect(described_class.group_ticket_title(['Ann', 'Bob'])).to eq('Group text with Ann, Bob')
    end
  end

  describe '#build_group_ticket_title' do
    it 'uses contact names where known and the number otherwise' do
      contacts = Class.new do
        def self.name_for(number) = { ANN => 'Ann Lee' }[number]
      end
      stub_const('Kc::PhoneContacts', contacts)
      expect(driver.send(:build_group_ticket_title, [ANN, BOB])).to eq("Group SMS: Ann Lee, #{BOB}")
    end
  end
end

RSpec.describe Channel::Driver::KcFreepbx do
  it 'keeps group texts off 1:1 tickets too' do
    expect(described_class.new.send(:conversation_key_candidates, OURS, [ANN, BOB]).size).to eq(1)
  end
end

RSpec.describe Kc::TeamsChatTitle do
  let(:members) do
    [{ 'userId' => 'me', 'displayName' => 'KawaConnect Support' },
     { 'userId' => 'u1', 'displayName' => 'Ann Lee' },
     { 'userId' => 'u2', 'displayName' => 'Bob Ray' }]
  end

  describe '.chat_name' do
    it 'uses the topic of a named group chat, commas and all', :aggregate_failures do
      expect(described_class.chat_name(chat_type: 'group', topic: ' Office move ', members: members)).to eq('Office move')
      expect(described_class.chat_name(chat_type: 'group', topic: 'Sales, Ops, IT', members: members)).to eq('Sales, Ops, IT')
    end

    it 'falls back to the member names without our own account' do
      expect(described_class.chat_name(chat_type: 'group', topic: nil, members: members, account_user_id: 'me'))
        .to eq('Ann Lee, Bob Ray')
    end

    it 'caps a long member list' do
      many = (1..6).map { |i| { 'userId' => "u#{i}", 'displayName' => "Person #{i}" } }
      expect(described_class.chat_name(chat_type: 'group', topic: '', members: many))
        .to eq('Person 1, Person 2, Person 3, Person 4, +2 more')
    end

    it 'names meeting chats after the meeting' do
      expect(described_class.chat_name(chat_type: 'meeting', topic: 'Weekly sync', members: members)).to eq('Weekly sync')
    end

    it 'is nil for 1:1 chats and unknown chats', :aggregate_failures do
      expect(described_class.chat_name(chat_type: 'oneOnOne', topic: nil, members: members)).to be_nil
      expect(described_class.chat_name(chat_type: 'group', topic: nil, members: [])).to be_nil
    end

    it 'never produces the old "Group Chat #hread.v2" name' do
      name = described_class.chat_name(chat_type: 'group', topic: nil, members: members, account_user_id: 'me')
      expect(described_class.group_title(name)).not_to include('hread.v2')
    end
  end

  describe '.group_title' do
    it 'fills the template', :aggregate_failures do
      expect(described_class.group_title('Office move')).to eq('Teams group chat: Office move')
      expect(described_class.group_title('Office move', template: '{chat_name} (Teams)')).to eq('Office move (Teams)')
      expect(described_class.group_title('x' * 200).length).to eq(100)
    end

    it 'ignores a template without the placeholder' do
      expect(described_class.group_title('Office move', template: 'Teams')).to eq('Teams group chat: Office move')
    end
  end

  describe '.replaceable?' do
    it 'replaces generated titles', :aggregate_failures do
      expect(described_class.replaceable?('Teams Message from Group Chat #hread.v2')).to be(true)
      expect(described_class.replaceable?('Teams Message from Ann Lee')).to be(true)
      expect(described_class.replaceable?('Teams group chat: Old topic', auto_title: 'Teams group chat: Old topic')).to be(true)
      expect(described_class.replaceable?('')).to be(true)
    end

    it 'never replaces a title an agent typed', :aggregate_failures do
      expect(described_class.replaceable?('Tax forms for 2026')).to be(false)
      expect(described_class.replaceable?('Teams Message from Ann - printer', auto_title: 'Teams group chat: Old')).to be(false)
    end

    it 'follows a custom 1:1 template' do
      expect(described_class.replaceable?('Chat with Ann Lee', template: 'Chat with {user_name}')).to be(true)
    end
  end
end

# 0.0.18: the "Earlier conversation" note of a group ticket quoted 1:1 texts
# between us and one member (ticket 188770: a three-person group text opened
# with two unrelated texts we had sent to one of them).
[Channel::Driver::KcRingcentralSms, Channel::Driver::KcFreepbx].each do |driver_class|
  RSpec.describe driver_class do
    subject(:driver) { described_class.new }

    let(:group) { [OURS, ANN, BOB, CARL] }

    it 'takes a message between exactly the group as the same conversation' do
      expect(driver.send(:same_conversation?, [ANN, OURS, CARL, BOB], group)).to be(true)
    end

    it 'does not take a 1:1 text with one member as the group conversation', :aggregate_failures do
      expect(driver.send(:same_conversation?, [OURS, ANN], group)).to be(false)
      expect(driver.send(:same_conversation?, [OURS, ANN, BOB], group)).to be(false)
    end

    it 'does not take a larger group or an empty list as this conversation', :aggregate_failures do
      expect(driver.send(:same_conversation?, group + ['+14125550104'], group)).to be(false)
      expect(driver.send(:same_conversation?, [], group)).to be(false)
    end

    it 'still matches a 1:1 conversation with itself' do
      expect(driver.send(:same_conversation?, [ANN, OURS], [OURS, ANN])).to be(true)
    end
  end
end
