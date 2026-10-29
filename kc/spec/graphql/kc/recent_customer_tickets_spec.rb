# KC: run in a Zammad test environment after copying kc/ into the app tree
# (kc/script/apply-overlay.sh, then cp -r kc/spec/. spec/):
#   bundle exec rspec spec/graphql/kc/recent_customer_tickets_spec.rb

require 'rails_helper'

RSpec.describe Kc::RecentCustomerTickets, :aggregate_failures do
  let(:group)    { create(:group) }
  let(:agent)    { create(:agent, groups: [group]) }
  let(:customer) { create(:customer) }
  let(:ticket)   { create(:ticket, group:, customer:, state_name: 'open', created_at: 10.days.ago) }

  let!(:open_ticket)    { create(:ticket, group:, customer:, state_name: 'open', created_at: 5.days.ago) }
  let!(:closed_new)     { create(:ticket, group:, customer:, state_name: 'closed', created_at: 2.days.ago) }
  let!(:closed_old)     { create(:ticket, group:, customer:, state_name: 'closed', created_at: 8.days.ago) }
  let!(:merged_shell) do
    create(:ticket, group:, customer:, state_name: 'open', created_at: 3.days.ago).tap do |shell|
      shell.merge_to(ticket_id: open_ticket.id, user_id: agent.id)
    end
  end
  let!(:other_customer) { create(:ticket, group:, state_name: 'closed') }

  before do
    # never listed: a merged-state ticket, and a closed ticket in a group the agent cannot read
    create(:ticket, group:, customer:, state_name: 'merged', created_at: 1.day.ago)
    create(:ticket, customer:, state_name: 'closed', created_at: 1.day.ago)
  end

  describe '.call' do
    def list(limit: 10)
      described_class.call(user: agent, customer_id: customer.id, except_ticket_id: ticket.id, limit:)
    end

    it 'lists open tickets first, then closed ones, newest first' do
      expect(merged_shell.reload.state.name).to eq('closed')
      expect(list).to eq([open_ticket, closed_new, closed_old])
    end

    it 'keeps upstream priority for open tickets when the limit is reached' do
      expect(list(limit: 1)).to eq([open_ticket])
      expect(list(limit: 2)).to eq([open_ticket, closed_new])
    end
  end

  describe Gql::Queries::Tickets::RecentByCustomer, type: :graphql do
    let(:query) do
      <<~QUERY
        query ticketsRecentByCustomer($customerId: ID!, $exceptTicketInternalId: Int, $limit: Int) {
          ticketsRecentByCustomer(customerId: $customerId, exceptTicketInternalId: $exceptTicketInternalId, limit: $limit) {
            id
          }
        }
      QUERY
    end

    before do
      gql.graphql_current_user = agent
      gql.execute(query, variables: { customerId: gql.id(customer), exceptTicketInternalId: ticket.id, limit: 10 })
    end

    it 'offers closed tickets as targets, but no merged ones' do
      expect(gql.result.data.pluck('id')).to eq([open_ticket, closed_new, closed_old].map { gql.id(it) })
    end
  end

  describe 'GET /api/v1/ticket_related (legacy UI)', type: :request do
    before do
      RecentView.log(other_customer, agent)
      authenticated_as(agent)
      get "/api/v1/ticket_related/#{ticket.id}", as: :json
    end

    it 'offers closed tickets as targets and keeps the recently viewed list' do
      expect(response).to have_http_status(:ok)
      expect(json_response['ticket_ids_by_customer']).to eq([open_ticket.id, closed_new.id, closed_old.id])
      expect(json_response['assets']['Ticket'].keys).to include(closed_new.id.to_s, closed_old.id.to_s)
      expect(json_response['ticket_ids_recent_viewed']).to include(other_customer.id)
    end
  end
end
