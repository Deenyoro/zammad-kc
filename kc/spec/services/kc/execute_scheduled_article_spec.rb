# KC: run in a Zammad test environment after copying kc/ into the app tree
# (kc/script/apply-overlay.sh, then cp -r kc/spec/. spec/):
#   bundle exec rspec spec/services/kc/execute_scheduled_article_spec.rb

require 'rails_helper'

RSpec.describe Kc::ExecuteScheduledArticle do
  let(:group)  { create(:group) }
  let(:agent)  { create(:agent, groups: [group]) }
  let(:ticket) { create(:ticket, group: group) }
  let(:scheduled) do
    Kc::ScheduledArticle.create!(
      ticket_id:     ticket.id,
      article_data:  { 'body' => 'later', 'type' => 'note', 'internal' => true },
      scheduled_at:  1.minute.from_now,
      status:        'pending',
      created_by_id: agent.id,
      updated_by_id: agent.id,
    )
  end

  # Kc::SendScheduledArticlesJob runs the service inside
  # UserInfo.with_user_id(scheduled.created_by_id); the new article takes its
  # created_by/updated_by from there, so the spec does the same.
  it 'sends while the agent still has change access', :aggregate_failures do
    expect { UserInfo.with_user_id(agent.id) { described_class.new(scheduled).execute! } }.to change { ticket.articles.count }.by(1)
    expect(scheduled.reload.status).to eq('sent')
    expect(ticket.articles.last).to have_attributes(created_by_id: agent.id, updated_by_id: agent.id)
  end

  it 'sends a due reply through the scheduler job as the scheduling agent', :aggregate_failures do
    scheduled.update!(scheduled_at: 1.minute.ago)

    expect { Kc::SendScheduledArticlesJob.perform_now }.to change { ticket.articles.count }.by(1)
    expect(scheduled.reload.status).to eq('sent')
    expect(ticket.articles.last).to have_attributes(body: 'later', created_by_id: agent.id)
  end

  it 'does not send once the agent lost change access', :aggregate_failures do
    scheduled
    agent.group_names_access_map = { group.name => %w[read] }

    expect { described_class.new(scheduled).execute! }.not_to change { ticket.articles.count }
    expect(scheduled.reload.status).to eq('failed')
    expect(scheduled.error_message).to include('no longer has change access')
  end

  it 'does not send for an inactive agent', :aggregate_failures do
    scheduled
    agent.update!(active: false)

    expect { described_class.new(scheduled).execute! }.not_to change { ticket.articles.count }
    expect(scheduled.reload.status).to eq('failed')
    expect(scheduled.error_message).to include('no longer active')
  end
end
