# KC: run in a Zammad test environment after copying kc/ into the app tree
# (kc/script/apply-overlay.sh, then cp -r kc/spec/. spec/):
#   bundle exec rspec spec/models/kc/merge_into_closed_ticket_spec.rb

require 'rails_helper'

RSpec.describe 'KC merge into a closed ticket', :aggregate_failures, type: :request do
  let(:group)           { create(:group) }
  let(:agent)           { create(:agent, groups: [group]) }
  let(:customer)        { create(:customer) }
  let(:closed_state)    { Ticket::State.find_by(name: 'closed') }
  let(:source_ticket)   { create(:ticket, group:, customer:, state_name: 'open') }
  let!(:source_article) { create(:ticket_article, ticket: source_ticket) }
  let(:target_ticket)   { create(:ticket, group:, customer:, state: closed_state) }

  def locked_state
    Ticket::State.find_by(name: 'closed (locked)') ||
      create(:ticket_state, name: 'closed (locked)', state_type: Ticket::StateType.find_by(name: 'closed'))
  end

  shared_examples 'a merge that leaves the closed target closed' do
    it 'moves the articles, closes the source and keeps the target closed' do
      perform_merge

      expect(source_article.reload.ticket_id).to eq(target_ticket.id)
      expect(target_ticket.reload.state.name).to eq('closed')
      expect(source_ticket.reload.state.name).to eq('closed')
      expect(source_ticket.kc_merged_shell?).to be(true)
      expect(source_ticket.articles.last.body).to include("merged into ticket ##{target_ticket.number}")
    end
  end

  describe 'Ticket#merge_to' do
    def perform_merge
      source_ticket.merge_to(ticket_id: target_ticket.id, user_id: agent.id)
    end

    it_behaves_like 'a merge that leaves the closed target closed'

    it 'keeps a locked target locked' do
      target_ticket.update!(state: locked_state)
      perform_merge

      expect(target_ticket.reload.state.name).to eq('closed (locked)')
      expect(source_article.reload.ticket_id).to eq(target_ticket.id)
    end

    it 'still refuses a closed target that was itself merged away' do
      other = create(:ticket, group:, customer:)
      target_ticket.merge_to(ticket_id: other.id, user_id: agent.id)

      expect { source_ticket.reload.merge_to(ticket_id: target_ticket.id, user_id: agent.id) }
        .to raise_error(Exceptions::UnprocessableContent, %r{already merged})
    end

    it 'reroutes follow-ups of the source to the closed target' do
      perform_merge

      expect(Channel::Filter::FollowUpMerged.find_merge_follow_up_ticket(source_ticket.reload)).to eq(target_ticket)
    end
  end

  describe 'Service::Ticket::Merge' do
    def perform_merge
      Service::Ticket::Merge.with_current_user(agent).execute(source_ticket:, target_ticket:)
    end

    it_behaves_like 'a merge that leaves the closed target closed'
  end

  describe 'REST ticket_merge (legacy UI)' do
    def perform_merge
      put "/api/v1/ticket_merge/#{source_ticket.id}/#{target_ticket.number}", params: {}, as: :json
      expect(json_response['result']).to eq('success')
    end

    before { authenticated_as(agent) }

    it_behaves_like 'a merge that leaves the closed target closed'
  end

  describe 'GraphQL ticketMerge (new desktop and mobile UI)', type: :graphql do
    let(:query) do
      <<~QUERY
        mutation ticketMerge($sourceTicketId: ID!, $targetTicketId: ID!) {
          ticketMerge(sourceTicketId: $sourceTicketId, targetTicketId: $targetTicketId) {
            targetTicket { id }
            errors { message }
          }
        }
      QUERY
    end

    def perform_merge
      gql.execute(query, variables: { sourceTicketId: gql.id(source_ticket), targetTicketId: gql.id(target_ticket) })
      expect(gql.result.data[:errors]).to be_nil
      expect(gql.result.data[:targetTicket][:id]).to eq(gql.id(target_ticket))
    end

    before { gql.graphql_current_user = agent }

    it_behaves_like 'a merge that leaves the closed target closed'
  end
end
