# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe FilterProcessor, type: :channel_filter do
  let(:mail_hash) { Channel::EmailParser.new.parse(<<~RAW.chomp) }
    From: daffy.duck@acme.corp
    To: batman@marvell.com
    Subject: Anvil

    I can haz anvil!
  RAW

  describe '.filter_matches?' do
    let(:filter) { create(:postmaster_filter, match: { 'from' => { 'operator' => operator, 'value' => value } }) }

    shared_examples 'the filter matches' do
      it 'matches' do
        expect(described_class.new(filter, mail_hash).filter_matches?).to be true
      end
    end

    shared_examples 'the filter does not match' do
      it 'matches' do
        expect(described_class.new(filter, mail_hash).filter_matches?).to be false
      end
    end

    context "with operator 'contains'" do
      let(:operator) { 'contains' }

      context 'with matching string' do
        let(:value) { 'a' }

        include_examples 'the filter matches'
      end

      context 'with matching upcased string' do
        let(:value) { 'A' }

        include_examples 'the filter matches'
      end

      context 'with non-matching string' do
        let(:value) { 'x' }

        include_examples 'the filter does not match'
      end
    end

    context "with operator 'contains not'" do
      let(:operator) { 'contains not' }

      context 'with matching string' do
        let(:value) { 'a' }

        include_examples 'the filter does not match'
      end

      context 'with matching upcased string' do
        let(:value) { 'A' }

        include_examples 'the filter does not match'
      end

      context 'with non-matching string' do
        let(:value) { 'x' }

        include_examples 'the filter matches'
      end
    end

    context "with operator 'matches regex'" do
      let(:operator) { 'matches regex' }

      context 'with matching string' do
        let(:value) { 'daffy.duck@.*' }

        include_examples 'the filter matches'
      end

      context 'with non-matching string' do
        let(:value) { 'daffy.duck.+@' }

        include_examples 'the filter does not match'
      end
    end

    context "with operator 'does not match regex'" do
      let(:operator) { 'does not match regex' }

      context 'with matching string' do
        let(:value) { 'daffy.duck@.*' }

        include_examples 'the filter does not match'
      end

      context 'with non-matching string' do
        let(:value) { 'daffy.duck.+@' }

        include_examples 'the filter matches'
      end
    end

    context "with operator 'is any of'" do
      let(:operator) { 'is any of' }

      context 'with matching string' do
        let(:value) { ['daffy.duck@acme.corp', 'elmer.fudd@acme.corp'] }

        include_examples 'the filter matches'
      end

      context 'with matching upcased string' do
        let(:value) { ['Daffy.Duck@acme.corp', 'Elmer.Fudd@acme.corp'] }

        include_examples 'the filter does not match'
      end

      context 'with non-matching string' do
        let(:value) { ['other.address@example.com', 'mail@example.com'] }

        include_examples 'the filter does not match'
      end
    end

    context "with operator 'is none of'" do
      let(:operator) { 'is none of' }

      context 'with matching string' do
        let(:value) { ['daffy.duck@acme.corp', 'elmer.fudd@acme.corp'] }

        include_examples 'the filter does not match'
      end

      context 'with matching upcased string' do
        let(:value) { ['Daffy.Duck@acme.corp', 'Elmer.Fudd@acme.corp'] }

        include_examples 'the filter matches'
      end

      context 'with non-matching string' do
        let(:value) { ['other.address@example.com', 'mail@example.com'] }

        include_examples 'the filter matches'
      end
    end

    context "with operator 'starts with one of'" do
      let(:operator) { 'starts with one of' }

      context 'with matching string' do
        let(:value) { ['daffy.duck', 'elmer.fudd'] }

        include_examples 'the filter matches'
      end

      context 'with matching upcased string' do
        let(:value) { ['Daffy.Duck', 'Elmer.Fudd'] }

        include_examples 'the filter matches'
      end

      context 'with non-matching string' do
        let(:value) { ['other.address', 'zammad.org'] }

        include_examples 'the filter does not match'
      end
    end

    context "with operator 'ends with one of'" do
      let(:operator) { 'ends with one of' }

      context 'with matching string' do
        let(:value) { ['acme.corp', 'example.com'] }

        include_examples 'the filter matches'
      end

      context 'with matching upcased string' do
        let(:value) { ['ACME.corp', 'EXAMPLE.com'] }

        include_examples 'the filter matches'
      end

      context 'with non-matching string' do
        let(:value) { ['example.com', 'zammad.org'] }

        include_examples 'the filter does not match'
      end
    end
  end
end
