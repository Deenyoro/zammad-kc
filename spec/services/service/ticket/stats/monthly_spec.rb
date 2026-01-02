# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Service::Ticket::Stats::Monthly, :aggregate_failures do
  subject(:service) { described_class.new(current_user: user) }

  let(:group) { create(:group) }
  let(:user)  { create(:agent, groups: [group]) }

  describe '#execute' do
    before do
      freeze_time
    end

    context 'with tickets in current month' do
      let!(:ticket_created) { create(:ticket, group: group, created_at: Time.zone.now) }
      let!(:ticket_closed)  { create(:ticket, group: group, created_at: 1.month.ago, close_at: Time.zone.now) }

      before { ticket_created && ticket_closed }

      it 'returns 12 months of data' do
        result = service.execute(conditions: {})

        expect(result).to be_an(Array)
        expect(result.size).to eq(12)
      end

      it 'includes correct keys in each month' do
        result = service.execute(conditions: {})

        expect(result.first.keys).to contain_exactly(:year, :month_number, :month_label, :tickets_created, :tickets_closed)
      end

      it 'counts tickets created in current month' do
        result = service.execute(conditions: {})

        current_month = result.first
        expect(current_month[:tickets_created]).to eq(1)
      end

      it 'counts tickets closed in current month' do
        result = service.execute(conditions: {})

        current_month = result.first
        expect(current_month[:tickets_closed]).to eq(1)
      end

      it 'includes correct month information' do
        result = service.execute(conditions: {})

        current_month = result.first
        now = Time.zone.now

        expect(current_month[:year]).to eq(now.year)
        expect(current_month[:month_number]).to eq(now.month)
        expect(current_month[:month_label]).to eq(Date::ABBR_MONTHNAMES[now.month])
      end
    end

    context 'with additional conditions' do
      let!(:open_ticket)   { create(:ticket, group: group, state: Ticket::State.find_by(name: 'open'), created_at: Time.zone.now) }
      let!(:closed_ticket) { create(:ticket, group: group, state: Ticket::State.find_by(name: 'closed'), created_at: Time.zone.now) }

      before { open_ticket && closed_ticket }

      it 'filters tickets by conditions' do
        result = service.execute(conditions: { state_id: Ticket::State.find_by(name: 'open').id })

        current_month = result.first
        expect(current_month[:tickets_created]).to eq(1)
      end
    end

    context 'with tickets across multiple months' do
      let!(:ticket_this_month)  { create(:ticket, group: group, created_at: Time.zone.now) }
      let!(:ticket_last_month)  { create(:ticket, group: group, created_at: 1.month.ago) }
      let!(:ticket_two_months)  { create(:ticket, group: group, created_at: 2.months.ago) }

      before { ticket_this_month && ticket_last_month && ticket_two_months }

      it 'distributes tickets correctly across months' do
        result = service.execute(conditions: {})

        expect(result[0][:tickets_created]).to eq(1)  # current month
        expect(result[1][:tickets_created]).to eq(1)  # last month
        expect(result[2][:tickets_created]).to eq(1)  # two months ago
        expect(result[3][:tickets_created]).to eq(0)  # three months ago
      end
    end

    context 'when user has no read access' do
      let(:other_group) { create(:group) }
      let!(:ticket)     { create(:ticket, group: other_group, created_at: Time.zone.now) }

      before { ticket }

      it 'does not count tickets from inaccessible groups' do
        result = service.execute(conditions: {})

        current_month = result.first
        expect(current_month[:tickets_created]).to eq(0)
      end
    end

    # https://github.com/zammad/zammad/issues/5865
    context 'when the ticket is created just before the new month' do
      let(:ticket) { create(:ticket, group: group, created_at: Time.zone.parse('2019-06-30 23:00')) }

      before do
        ticket
        Setting.set('timezone_default', timezone)
        travel_to Time.zone.parse('2019-07-02 01:00')
      end

      context 'when time zome is ahead of UTC' do
        let(:timezone) { 'Asia/Tokyo' }

        it 'returns tickets according to Zammad time zone' do
          result = service.execute(conditions: {})

          current_month = result.first
          previous_month = result.second
          expect(current_month[:tickets_created]).to eq(1)
          expect(previous_month[:tickets_created]).to eq(0)
        end
      end

      context 'when time zone is behind UTC' do
        let(:timezone) { 'America/New_York' }

        it 'returns tickets according to Zammad time zone' do
          result = service.execute(conditions: {})

          current_month = result.first
          previous_month = result.second
          expect(current_month[:tickets_created]).to eq(0)
          expect(previous_month[:tickets_created]).to eq(1)
        end
      end
    end
  end
end
