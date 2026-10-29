# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# KC: run in a Zammad test environment after copying kc/ into the app tree
# (kc/script/apply-overlay.sh, then cp -r kc/spec/. spec/):
#   bundle exec rspec spec/services/kc/execute_scheduled_article_bcc_spec.rb
#
# Scheduled email replies keep their BCC recipients when they are sent
# (both UIs store bcc in article_data).

require 'rails_helper'

RSpec.describe Kc::ExecuteScheduledArticle, performs_jobs: true do
  let(:group)  { create(:group) } # factory default: email address on a sendmail channel
  let(:agent)  { create(:agent, groups: [group]) }
  let(:ticket) { create(:ticket, group: group) }
  let(:scheduled) do
    Kc::ScheduledArticle.create!(
      ticket_id:     ticket.id,
      article_data:  {
        'body'         => 'scheduled with a blind copy',
        'type'         => 'email',
        'internal'     => false,
        'content_type' => 'text/plain',
        'subject'      => 'KC scheduled BCC',
        'to'           => 'kc-sched-to@example.com',
        'cc'           => 'kc-sched-cc@example.com',
        'bcc'          => 'kc-sched-bcc@example.com',
      },
      scheduled_at:  1.minute.from_now,
      status:        'pending',
      created_by_id: agent.id,
      updated_by_id: agent.id,
    )
  end

  before do
    scheduled
    clear_jobs
    Mail::TestMailer.deliveries.clear
  end

  it 'keeps bcc on the sent article and in the outbound mail', :aggregate_failures do
    article = UserInfo.with_user_id(agent.id) { described_class.new(scheduled).execute! }

    expect(scheduled.reload.status).to eq('sent')
    expect(article.reload).to have_attributes(to: 'kc-sched-to@example.com', cc: 'kc-sched-cc@example.com', bcc: 'kc-sched-bcc@example.com')

    perform_enqueued_jobs(only: TicketArticleCommunicateEmailJob)

    expect(Mail::TestMailer.deliveries.last.bcc).to contain_exactly('kc-sched-bcc@example.com')
  end
end
