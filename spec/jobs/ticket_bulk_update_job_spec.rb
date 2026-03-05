# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe TicketBulkUpdateJob do
  describe '#perform' do
    let(:group)   { create(:group) }
    let(:user)    { create(:agent, groups: [group]) }
    let(:perform) { { input: { title: 'New Title' } } }
    let(:ticket)  { create(:ticket, group:) }

    context 'with one ticket' do
      it 'passes given perform argument for the ticket to update service' do
        allow(Service::Ticket::Bulk::SingleItemUpdate)
          .to receive(:new)
          .and_call_original

        described_class
          .perform_now(user:, perform:, ticket_ids: [ticket.id])

        expect(Service::Ticket::Bulk::SingleItemUpdate)
          .to have_received(:new)
          .with(user:, ticket:, perform:)
          .once
      end

      it 'calls final subscription after all tickets are updated' do
        allow(Gql::Subscriptions::User::Current::Ticket::BulkUpdateStatusUpdates)
          .to receive(:trigger)

        described_class
          .perform_now(user:, perform:, ticket_ids: [ticket.id])

        expect(Gql::Subscriptions::User::Current::Ticket::BulkUpdateStatusUpdates)
          .to have_received(:trigger)
          .with({ status: 'succeeded', total: 1, failed_count: 0 }, scope: user.id)
      end

      context 'when a ticket update fails' do
        let(:other_ticket) { create(:ticket) }

        it 'calls final subscription with failed ticket count' do
          allow(Gql::Subscriptions::User::Current::Ticket::BulkUpdateStatusUpdates)
            .to receive(:trigger)

          described_class
            .perform_now(user:, perform:, ticket_ids: [other_ticket.id, ticket.id])

          expect(Gql::Subscriptions::User::Current::Ticket::BulkUpdateStatusUpdates)
            .to have_received(:trigger)
            .with({ status: 'failed', total: 2, failed_count: 1 }, scope: user.id)
        end
      end
    end

    context 'with multiple tickets', aggregate_failures: true do
      let(:tickets) { create_list(:ticket, 250, group:) }

      it 'processes a batch of tickets' do
        allow(Service::Ticket::Bulk::SingleItemUpdate)
          .to receive(:new)
          .and_call_original

        described_class
          .perform_now(user:, perform:, ticket_ids: tickets.pluck(:id))

        expect(Service::Ticket::Bulk::SingleItemUpdate)
          .to have_received(:new)
          .exactly(described_class::TICKETS_PER_JOB_COUNT)

        expect(Service::Ticket::Bulk::SingleItemUpdate)
          .to have_received(:new)
          .with(user:, ticket: tickets[0], perform:)
          .once

        expect(Service::Ticket::Bulk::SingleItemUpdate)
          .to have_received(:new)
          .with(user:, ticket: tickets[99], perform:)

        expect(Service::Ticket::Bulk::SingleItemUpdate)
          .not_to have_received(:new)
          .with(user:, ticket: tickets[100], perform:)
      end

      it 'updates subscription progress every few tickets' do
        expect_any_instance_of(described_class).to receive(:update_subscription_progress).twice

        described_class
          .perform_now(user:, perform:, ticket_ids: tickets.slice(0, 22))
      end

      it 'enqueues next batch of tickets' do
        allow(described_class).to receive(:perform_later)

        described_class
          .perform_now(user:, perform:, ticket_ids: tickets.pluck(:id))

        expect(described_class)
          .to have_received(:perform_later)
          .with(
            user:,
            perform:,
            ticket_ids:        tickets.slice(100..).pluck(:id),
            total:             250,
            processed_count:   100,
            failed_ticket_ids: []
          )
      end

      it 'does not call final subscription until all batches are processed' do
        allow(Gql::Subscriptions::User::Current::Ticket::BulkUpdateStatusUpdates)
          .to receive(:trigger)

        described_class
          .perform_now(user:, perform:, ticket_ids: tickets.pluck(:id))

        expect(Gql::Subscriptions::User::Current::Ticket::BulkUpdateStatusUpdates)
          .not_to have_received(:trigger)
          .with(hash_including(status: 'succeeded'), scope: user.id)
      end

      it 'calls final subscription after all tickets are updated' do
        allow(Gql::Subscriptions::User::Current::Ticket::BulkUpdateStatusUpdates)
          .to receive(:trigger)

        described_class
          .perform_now(user:, perform:, ticket_ids: tickets.slice(200..).pluck(:id), total: 250, processed_count: 200)

        expect(Gql::Subscriptions::User::Current::Ticket::BulkUpdateStatusUpdates)
          .to have_received(:trigger)
          .with({ status: 'succeeded', total: 250, failed_count: 0 }, scope: user.id)
      end

      it 'calls final subscription with failed ticket count if some updates in earlier batch failed' do
        allow(Gql::Subscriptions::User::Current::Ticket::BulkUpdateStatusUpdates)
          .to receive(:trigger)

        described_class
          .perform_now(user:, perform:, ticket_ids: tickets.slice(200..).pluck(:id), total: 250, failed_ticket_ids: [123])

        expect(Gql::Subscriptions::User::Current::Ticket::BulkUpdateStatusUpdates)
          .to have_received(:trigger)
          .with({ status: 'failed', total: 250, failed_count: 1 }, scope: user.id)
      end
    end
  end

  describe '.fetch_running_status' do
    let(:user) { create(:agent) }

    context 'when no job is running for the user' do
      it 'returns status as none' do
        expect(described_class.fetch_running_status(user)).to eq(status: 'none')
      end
    end

    context 'when a job is running for the user' do
      let(:processed_count) { nil }
      let(:total)           { nil }

      before do
        described_class.perform_later(user:, perform: {}, ticket_ids: [1, 2, 3], processed_count:, total:)
      end

      context 'when the job is currently performing' do
        it 'returns status as pending, and the counts' do
          Delayed::Job.last.update! locked_at: 1.minute.ago, locked_by: 'test-worker'

          expect(described_class.fetch_running_status(user))
            .to include(status: 'running', total: 3, processed_count: 0)
        end
      end

      context 'when the kick-off job is waiting to be performed' do
        it 'returns status as running, and the counts' do
          expect(described_class.fetch_running_status(user))
            .to include(status: 'pending', total: 3, processed_count: 0)
        end
      end

      context 'when a later job is waiting to be performed' do
        let(:processed_count) { 20 }
        let(:total)           { 23 }

        it 'returns status as running, and the counts' do
          expect(described_class.fetch_running_status(user))
            .to include(status: 'running', total: 23, processed_count: 20)
        end
      end
    end
  end
end
