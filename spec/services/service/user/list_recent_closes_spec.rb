# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Service::User::ListRecentCloses do
  describe '#execute' do
    let(:group)        { create(:group) }
    let(:user)         { create(:agent, groups: [group]) }
    let(:ticket1)      { create(:ticket, group:) }
    let(:ticket2)      { create(:ticket, group:) }
    let(:ticket3)      { create(:ticket, group:) }
    let(:organization) { create(:organization) }
    let(:closed_user)  { create(:user) }

    context 'with many recent closes' do
      before do
        create(:recent_close, user:, recently_closed_object: ticket1, updated_at: 2.days.ago)
        create(:recent_close, user:, recently_closed_object: organization, updated_at: 1.day.ago)
        create(:recent_close, user:, recently_closed_object: ticket2, updated_at: 3.days.ago)
        create(:recent_close, user:, recently_closed_object: ticket3, updated_at: 3.hours.ago)
        create(:recent_close, user:, recently_closed_object: closed_user, updated_at: 1.week.ago)
      end

      it 'returns recently closed objects in correct order' do
        result = described_class.new(user).execute

        expect(result).to eq([ticket3, organization, ticket1, ticket2, closed_user])
      end

      it 'respects the limit parameter' do
        result = described_class.new(user, limit: 2).execute

        expect(result).to eq([ticket3, organization])
      end

      it 'returns only objects the user has access to' do
        expect { ticket2.update!(group: create(:group)) }
          .to change { described_class.new(user).execute }
          .from([ticket3, organization, ticket1, ticket2, closed_user])
          .to([ticket3, organization, ticket1, closed_user])
      end
    end
  end
end
