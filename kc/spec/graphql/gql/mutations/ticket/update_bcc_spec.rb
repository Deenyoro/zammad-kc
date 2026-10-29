# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# KC: run in a Zammad test environment after copying kc/ into the app tree
# (kc/script/apply-overlay.sh, then cp -r kc/spec/. spec/):
#   bundle exec rspec spec/graphql/gql/mutations/ticket/update_bcc_spec.rb
#
# The new desktop UI and mobile send email replies through the ticketUpdate
# mutation. This covers the BCC chain end to end: GraphQL article input ->
# ticket_articles.bcc (Kc::ArticlePreprocessBcc) -> outbound mail Bcc
# (Kc::EmailJobBcc + Kc::EmailOutboundBcc), without leaking the BCC
# recipients into the headers every recipient sees.

require 'rails_helper'

RSpec.describe Gql::Mutations::Ticket::Update, :aggregate_failures, authenticated_as: :agent, performs_jobs: true, type: :graphql do
  let(:query) do
    <<~QUERY
      mutation ticketUpdate($ticketId: ID!, $input: TicketUpdateInput!) {
        ticketUpdate(ticketId: $ticketId, input: $input) {
          ticket {
            id
          }
          errors {
            message
            field
          }
        }
      }
    QUERY
  end

  let(:group)    { create(:group) } # factory default: email address on a sendmail channel
  let(:agent)    { create(:agent, groups: [group]) }
  let(:customer) { create(:customer, email: 'kc-bcc-customer@example.com') }
  let(:ticket)   { create(:ticket, group: group, customer: customer, owner: agent) }

  let(:article_payload) do
    {
      body:        'Reply with a blind copy',
      type:        'email',
      internal:    false,
      contentType: 'text/plain',
      subject:     'KC BCC reply',
      to:          ['kc-bcc-customer@example.com'],
      cc:          ['kc-bcc-cc@example.com'],
      bcc:         ['kc-bcc-hidden-1@example.com', 'kc-bcc-hidden-2@example.com'],
    }
  end

  let(:variables) do
    {
      ticketId: gql.id(ticket),
      input:    {
        title:      ticket.title,
        groupId:    gql.id(group),
        priorityId: gql.id(ticket.priority),
        stateId:    gql.id(ticket.state),
        customer:   { id: gql.id(customer) },
        ownerId:    gql.id(agent),
        article:    article_payload,
      },
    }
  end

  before do
    ticket
    clear_jobs
    Mail::TestMailer.deliveries.clear
  end

  it 'stores the article BCC and delivers it as envelope-only Bcc' do
    expect { gql.execute(query, variables: variables) }.to change(Ticket::Article, :count).by(1)
    expect(gql.result.data[:errors]).to be_nil

    article = ticket.reload.articles.last
    expect(article).to have_attributes(
      to:  'kc-bcc-customer@example.com',
      cc:  'kc-bcc-cc@example.com',
      bcc: 'kc-bcc-hidden-1@example.com, kc-bcc-hidden-2@example.com',
    )

    perform_enqueued_jobs(only: TicketArticleCommunicateEmailJob)

    mail = Mail::TestMailer.deliveries.last
    expect(mail).to be_present
    expect(mail.bcc).to contain_exactly('kc-bcc-hidden-1@example.com', 'kc-bcc-hidden-2@example.com')
    expect(mail.smtp_envelope_to).to include('kc-bcc-customer@example.com', 'kc-bcc-cc@example.com',
                                             'kc-bcc-hidden-1@example.com', 'kc-bcc-hidden-2@example.com')

    # The transmitted message must not reveal the blind copies.
    expect(mail.encoded).not_to include('kc-bcc-hidden-1@example.com')
    expect(mail.encoded).not_to include('kc-bcc-hidden-2@example.com')
  end

  context 'without bcc' do
    let(:article_payload) { super().except(:bcc) }

    it 'stores an empty BCC and sends no Bcc' do
      gql.execute(query, variables: variables)

      expect(ticket.reload.articles.last.bcc).to eq('')

      perform_enqueued_jobs(only: TicketArticleCommunicateEmailJob)

      expect(Mail::TestMailer.deliveries.last.bcc).to be_blank
    end
  end
end
