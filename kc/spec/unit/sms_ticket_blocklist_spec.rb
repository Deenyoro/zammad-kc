# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rspec'
require 'active_support/all'

Time.zone = 'UTC'

module Kc; end
class Setting
  module Validation; end
end
class Channel
  module Driver; end
end
class Ticket
  class Article; end
end

root = File.expand_path('../../..', __dir__)
require File.join(root, 'kc/lib/kc/sms_ticket_blocklist')
require File.join(root, 'app/models/setting/validation/base')
require File.join(root, 'kc/app/models/setting/validation/kc_sms_ticket_blocklist')
require File.join(root, 'kc/app/models/channel/driver/kc_ringcentral_sms')
require File.join(root, 'kc/app/models/channel/driver/kc_freepbx')

RSpec.describe Kc::SmsTicketBlocklist do
  let(:blocked) { '+1 (412) 555-0100' }

  before do
    allow(Setting).to receive(:get).with(described_class::SETTING_NAME).and_return(blocked)
  end

  it 'matches formatted national and international numbers exactly' do
    expect(described_class.blocked?('4125550100')).to be(true)
    expect(described_class.blocked?('+14125550100')).to be(true)
    expect(described_class.blocked?('+14125550101')).to be(false)
    expect(described_class.blocked?('5550100')).to be(false)
  end

  it 'preserves an explicit international country code' do
    expect(described_class.normalize('+33 12345678')).to eq('+3312345678')
  end

  it 'accepts newlines and comma separated lists without splitting formatted numbers' do
    expect(described_class.entries("+1 (412) 555-0100\n+442079460100, 55555")).to eq(['+1 (412) 555-0100', '+442079460100', '55555'])
  end

  context 'with no blocked numbers' do
    let(:blocked) { '' }

    it 'leaves all numbers enabled' do
      expect(described_class.blocked?('+14125550100', nil)).to be(false)
    end
  end

  it 'rejects malformed configuration rather than silently ignoring it' do
    expect { described_class.validate!('all numbers') }.to raise_error(ArgumentError)
    expect { described_class.validate!(['4125550100']) }.to raise_error(ArgumentError)
    expect { described_class.validate!('+1 412 555 0100; +442079460100') }.not_to raise_error
  end

  it 'returns a validation failure for API and settings form writes' do
    record = Struct.new(:state_current).new({ 'value' => 'not a number' })
    expect(Setting::Validation::KcSmsTicketBlocklist.new(record).run[:success]).to be(false)
  end

  [Channel::Driver::KcRingcentralSms, Channel::Driver::KcFreepbx].each do |driver_class|
    context driver_class.name do
      subject(:driver) { driver_class.new }

      let(:message) do
        { message_id: 'example-id', from_phone: '4125550100', to_phone: '+14125550199', to_phones: ['+14125550199'] }
      end

      it 'skips inbound messages before database, contact, attachment, and ticket processing' do
        expect(Ticket::Article).not_to receive(:exists?)
        expect(driver.process({}, message, nil)).to be_nil
      end

      it 'skips blocked participants in group texts, including when another customer sent the message' do
        data = message.merge(from_phone: '+14125550101', to_phones: ['+14125550199', '+14125550100'])
        expect(Ticket::Article).not_to receive(:exists?)
        expect(driver.process({}, data, nil)).to be_nil
      end

      it 'also filters string-keyed provider messages' do
        data = message.merge(from_phone: '+14125550199', to_phone: '+14125550100', to_phones: ['+14125550100']).stringify_keys
        expect(Ticket::Article).not_to receive(:exists?)
        expect(driver.outbound_capture_plan(nil, data)).to eq(action: :skip_blocked_number)
      end

      %i[live backfill].each do |mode|
        it "skips outbound captures in #{mode} mode without touching a ticket" do
          data = message.merge(from_phone: '+14125550199', to_phone: '+14125550100', to_phones: ['+14125550100'])
          expect(Ticket::Article).not_to receive(:exists?)
          expect(driver.outbound_capture_plan(nil, data, mode: mode)).to eq(action: :skip_blocked_number)
        end
      end

      it 'filters blocked messages fetched as earlier conversation context' do
        allow(driver).to receive(:context_message_count).and_return(5)
        allow(driver).to receive(:normalize_phone) { |number| Kc::SmsTicketBlocklist.normalize(number) }
        api = double('provider')
        if driver_class == Channel::Driver::KcRingcentralSms
          stub_const('Kc::RingcentralApi', Class.new)
          allow(Kc::RingcentralApi).to receive(:with_channel_tokens).and_return(api)
          record = { id: 'older-id', type: 'SMS', direction: 'Inbound', creationTime: '2026-01-01T00:00:00Z', from: { phoneNumber: '+14125550100' }, to: [{ phoneNumber: '+14125550199' }], subject: 'private reply' }
          allow(api).to receive(:get_message_store).and_return({ 'records' => [record] })
        else
          stub_const('Kc::FreepbxApi', Class.new)
          allow(Kc::FreepbxApi).to receive(:for_channel).and_return(api)
          record = { id: 'older-id', from: '+14125550100', to: ['+14125550199'], text: 'private reply', created_at: '2026-01-01T00:00:00Z' }
          allow(api).to receive(:sms_messages).and_return([record])
        end
        expect(driver).not_to receive(:create_context_article)
        driver.send(:add_context_note, double('ticket'), nil, '+14125550199', ['+14125550100'], before: '2026-01-02T00:00:00Z')
      end

      it 'preserves the normal deduplication path for an allowed sender' do
        data = message.merge(from_phone: '+14125550101')
        expect(Ticket::Article).to receive(:exists?).and_return(true)
        expect(driver.process({}, data, nil)).to be_nil
      end
    end
  end
end
