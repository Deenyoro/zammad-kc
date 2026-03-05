# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Service::Ticket::Bulk::UpdateInline do
  let(:group)      { create(:group) }
  let(:user)       { create(:agent, groups: [group]) }
  let(:tickets)    { create_list(:ticket, 3, group:) }
  let(:perform)    { { input: { title: 'new title' } } }
  let(:ticket_ids) { tickets.map(&:id) }
  let(:instance)   { described_class.new(user:, ticket_ids:, perform:) }

  describe '#execute' do
    it 'passes given tickets to single item update', aggregate_failures: true do
      allow(Service::Ticket::Bulk::SingleItemUpdate).to receive(:new).and_call_original

      instance.execute

      expect(Service::Ticket::Bulk::SingleItemUpdate)
        .to have_received(:new)
        .with(user:, ticket: tickets[0], perform:)

      expect(Service::Ticket::Bulk::SingleItemUpdate)
        .to have_received(:new)
        .with(user:, ticket: tickets[1], perform:)

      expect(Service::Ticket::Bulk::SingleItemUpdate)
        .to have_received(:new)
        .with(user:, ticket: tickets[2], perform:)
    end

    it 'returns async false and the counts' do
      expect(instance.execute).to include(
        async:                false,
        total:                tickets.size,
        failed_count:         0,
        inaccessible_tickets: [],
        invalid_tickets:      []
      )
    end

    context 'when passing an inaccessible ticket id' do
      let(:inaccessible_ticket) { tickets[1] }

      before do
        error = Service::Ticket::Bulk::SingleItemUpdate::BulkSingleError.new(
          record:         inaccessible_ticket,
          original_error: Pundit::NotAuthorizedError.new(record: inaccessible_ticket, message: 'not authorized')
        )

        allow(Service::Ticket::Bulk::SingleItemUpdate)
          .to receive(:new)
          .and_call_original

        allow(Service::Ticket::Bulk::SingleItemUpdate)
          .to receive(:new)
          .with(user:, ticket: tickets[1], perform:)
          .and_raise(error)
      end

      it 'returns inaccessible ticket ids' do
        expect(instance.execute).to include(
          async:                false,
          total:                3,
          failed_count:         1,
          inaccessible_tickets: [inaccessible_ticket],
          invalid_tickets:      []
        )
      end
    end

    context 'when passing an invalid ticket id' do
      let(:invalid_ticket) { tickets[0] }

      before do
        error = Service::Ticket::Bulk::SingleItemUpdate::BulkSingleError.new(
          record:         invalid_ticket,
          original_error: ActiveRecord::RecordInvalid.new(invalid_ticket)
        )

        allow(Service::Ticket::Bulk::SingleItemUpdate)
          .to receive(:new)
          .and_call_original

        allow(Service::Ticket::Bulk::SingleItemUpdate)
          .to receive(:new)
          .with(user:, ticket: tickets[1], perform:)
          .and_raise(error)
      end

      it 'returns invalid ticket ids' do
        expect(instance.execute).to include(
          async:                false,
          total:                3,
          failed_count:         1,
          invalid_tickets:      [invalid_ticket],
          inaccessible_tickets: []
        )
      end
    end
  end
end
