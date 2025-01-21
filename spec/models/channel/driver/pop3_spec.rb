# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Channel::Driver::Pop3 do
  describe '#check_configuration' do
    before do
      stub_const('MockedMessage', Struct.new(:pop))

      allow_any_instance_of(Net::POP3)
        .to receive(:start)

      allow_any_instance_of(Net::POP3)
        .to receive(:finish)

      allow_any_instance_of(Net::POP3)
        .to receive(:enable_ssl)

      allow_any_instance_of(Net::POP3)
        .to receive(:mails)
        .and_return(message_ids)
    end

    def mock_a_message(verify: false)
      attrs = {
        from:         Faker::Internet.unique.email,
        to:           Faker::Internet.unique.email,
        body:         Faker::Lorem.sentence,
        content_type: 'text/html',
      }

      if verify
        attrs[:'X-Zammad-Ignore'] = 'true'
        attrs[:'X-Zammad-Verify'] = 'true'
        attrs[:'X-Zammad-Verify-Time'] = Time.current.to_s
      end

      Channel::EmailBuild.build(**attrs).to_s
    end

    context 'when no messages exist' do
      let(:message_ids) { [] }

      it 'finds no content messages' do
        response = described_class
          .new
          .check_configuration({})

        expect(response).to include(
          result:           'ok',
          content_messages: be_zero,
        )
      end
    end

    context 'when a verify message exist' do
      let(:message_ids) do
        [
          MockedMessage.new(mock_a_message(verify: true)),
        ]
      end

      it 'finds no content messages' do
        response = described_class
          .new
          .check_configuration({})

        expect(response).to include(
          result:           'ok',
          content_messages: be_zero,
        )
      end
    end

    context 'when some content messages exist' do
      let(:message_ids) do
        [
          MockedMessage.new(mock_a_message),
          MockedMessage.new(mock_a_message),
          MockedMessage.new(mock_a_message),
        ]
      end

      it 'finds content messages' do
        response = described_class
          .new
          .check_configuration({})

        expect(response).to include(
          result:           'ok',
          content_messages: 3,
        )
      end
    end

    context 'when a verify and a content message exists' do
      let(:message_ids) do
        [
          MockedMessage.new(mock_a_message(verify: true)),
          MockedMessage.new(mock_a_message),
        ]
      end

      it 'finds content messages' do
        response = described_class
          .new
          .check_configuration({})

        expect(response).to include(
          result:           'ok',
          content_messages: 2,
        )
      end
    end
  end
end
