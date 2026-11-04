# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Runs the actual service and all three drivers against an isolated in-memory
# database. No Zammad installation, production database or external APIs needed.
# ruby kc/test/recent_conversation_reopen_test.rb
require 'active_record'
require 'active_support/all'
require 'active_support/testing/time_helpers'
ARGV.unshift('--options', File::NULL)
require 'rspec/autorun'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:ticket_state_types) { |t| t.string :name }
  create_table(:ticket_states) do |t|
    t.string :name
    t.integer :state_type_id
    t.boolean :default_follow_up, default: false
  end
  create_table(:tickets) do |t|
    t.integer :state_id
    t.integer :updated_by_id
    t.datetime :close_at
    t.datetime :last_close_at
    t.datetime :pending_time
    t.text :preferences
    t.timestamps
  end
end

module Kc; end
class Ticket < ActiveRecord::Base
  serialize :preferences, coder: YAML
  belongs_to :state, class_name: 'Ticket::State'
  class StateType < ActiveRecord::Base; end
  class State < ActiveRecord::Base
    belongs_to :state_type, class_name: 'Ticket::StateType'
  end
end
class Channel
  module Driver; end
end

repo = File.expand_path('../..', __dir__)
require "#{repo}/kc/app/services/kc/recent_conversation_reopen"
%w[kc_ringcentral_sms kc_freepbx kc_microsoft_teams_chat].each do |name|
  require "#{repo}/kc/app/models/channel/driver/#{name}"
end

RSpec.configure do |config|
  config.include ActiveSupport::Testing::TimeHelpers
  config.before do
    Time.zone = 'UTC'
    travel_to Time.zone.parse('2026-11-04 12:00:00')
    Ticket.delete_all
    Ticket::State.delete_all
    Ticket::StateType.delete_all
  end
  config.after { travel_back }
end

RSpec.describe Kc::RecentConversationReopen do
  let(:closed_type) { Ticket::StateType.create!(name: 'closed') }
  let(:open_type) { Ticket::StateType.create!(name: 'open') }
  let!(:open_state) { Ticket::State.create!(name: 'open', state_type: open_type, default_follow_up: true) }
  let(:closed_state) { Ticket::State.create!(name: 'closed', state_type: closed_type) }
  let(:key) { '+14125550100:+14125550111' }
  let(:prefs_key) { :ringcentral_sms }
  let(:channel_id) { 7 }
  let(:at) { Time.current }
  let(:ticket) { conversation }

  def conversation(closed_at: 5.minutes.ago, first_close: closed_at, state: closed_state, key: self.key, prefs_key: self.prefs_key, channel_id: self.channel_id)
    Ticket.create!(state: state, last_close_at: closed_at, close_at: first_close,
                   pending_time: 1.hour.from_now,
                   preferences: { prefs_key => { conversation_key: key, channel_id: channel_id } })
  end

  def reopen
    described_class.call(preferences_key: prefs_key, conversation_key: key,
                         message_time: at, user_id: 42, channel_id: channel_id)
  end

  it 'reopens the same ticket and clears its pending timer without creating another ticket' do
    ticket
    expect { expect(reopen.id).to eq(ticket.id) }.not_to change(Ticket, :count)
    expect(ticket.reload).to have_attributes(state_id: open_state.id, updated_by_id: 42, pending_time: nil)
  end

  it 'includes exactly fifteen minutes after closure' do
    ticket.update!(last_close_at: 15.minutes.ago)
    expect(reopen.id).to eq(ticket.id)
  end

  it 'does not reopen after fifteen minutes' do
    ticket.update!(last_close_at: 15.minutes.ago - 1.second)
    expect(reopen).to be_nil
    expect(ticket.reload.state).to eq(closed_state)
  end

  it 'uses the latest closure rather than the first closure or update time' do
    ticket.update!(close_at: 1.month.ago, last_close_at: 1.minute.ago, updated_at: 1.day.ago)
    expect(reopen.id).to eq(ticket.id)
  end

  it 'does not extend the window when a closed ticket is edited' do
    ticket.update!(last_close_at: 1.day.ago, updated_at: Time.current)
    expect(reopen).to be_nil
  end

  it 'falls back to close_at for a ticket without last_close_at' do
    ticket.update!(last_close_at: nil)
    expect(reopen.id).to eq(ticket.id)
  end

  it 'uses the original message time when delivery is delayed' do
    ticket.update!(last_close_at: 20.minutes.ago)
    allow(self).to receive(:at).and_return(10.minutes.ago)
    expect(reopen.id).to eq(ticket.id)
  end

  it 'ignores a message from before the latest closure' do
    ticket
    allow(self).to receive(:at).and_return(10.minutes.ago)
    expect(reopen).to be_nil
  end

  it 'selects the most recently closed matching ticket' do
    ticket
    newer = conversation(closed_at: 1.minute.ago)
    expect(reopen.id).to eq(newer.id)
    expect(ticket.reload.state).to eq(closed_state)
  end

  it 'does not match another SMS group containing the same number' do
    conversation(key: "#{key}:+14125550122")
    expect(reopen).to be_nil
  end

  it 'does not match the same number on another channel' do
    conversation(channel_id: 8)
    expect(reopen).to be_nil
  end

  it 'does not match another integration with the same conversation key' do
    conversation(prefs_key: :freepbx_sms)
    expect(reopen).to be_nil
  end

  it 'does not treat SQL wildcards as matching other conversations' do
    conversation(key: 'tenant:chatXYZ')
    allow(self).to receive(:key).and_return('tenant:chat%')
    expect(reopen).to be_nil
  end

  ['closed (locked)', 'closed (locked until)'].each do |name|
    it "preserves #{name}" do
      locked = Ticket::State.create!(name: name, state_type: closed_type)
      t = conversation(state: locked)
      expect(reopen).to be_nil
      expect(t.reload.state).to eq(locked)
    end
  end

  it 'does not reopen merged tickets' do
    merged = Ticket::State.create!(name: 'merged', state_type: Ticket::StateType.create!(name: 'merged'))
    conversation(state: merged)
    expect(reopen).to be_nil
  end

  it 'ignores a record with no closure timestamp' do
    conversation(closed_at: nil)
    expect(reopen).to be_nil
  end

  [nil, 'not a timestamp'].each do |value|
    it "uses receipt time when the source timestamp is #{value.inspect}" do
      ticket
      allow(self).to receive(:at).and_return(value)
      expect(reopen.id).to eq(ticket.id)
    end
  end

  [[:ringcentral_sms, Channel::Driver::KcRingcentralSms],
   [:freepbx_sms, Channel::Driver::KcFreepbx],
   [:teams_chat, Channel::Driver::KcMicrosoftTeamsChat]].each do |integration, driver_class|
    context "#{integration} driver" do
      let(:prefs_key) { integration }
      let(:driver) { driver_class.new }
      let(:channel) { Struct.new(:id, :options).new(channel_id, {}) }
      let(:user) { Struct.new(:id).new(42) }

      before do
        allow(driver).to receive(:find_existing_ticket).and_return(nil)
        allow(driver).to receive(:thread_window_hours).and_return(24)
        if integration == :teams_chat
          allow(driver).to receive(:build_conversation_key).and_return(key)
        else
          allow(driver).to receive(:conversation_key_candidates).and_return([key])
          allow(driver).to receive(:conversation_key).and_return(key)
        end
      end

      def route
        args = [channel, { created_at: at }, user]
        args += ['+14125550100', ['+14125550111']] unless prefs_key == :teams_chat
        driver.send(:find_or_create_ticket, *args)
      end

      it 'returns the reopened ticket to the existing article/attachment pipeline' do
        ticket
        expect(Ticket).not_to receive(:new)
        expect(route.id).to eq(ticket.id)
        expect(ticket.reload.state).to eq(open_state)
      end

      it 'prefers an existing open conversation' do
        existing = conversation(state: open_state)
        allow(driver).to receive(:find_existing_ticket).and_return(existing)
        expect(described_class).not_to receive(:call)
        expect(route.id).to eq(existing.id)
      end
    end
  end
end
