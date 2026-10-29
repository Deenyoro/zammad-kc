# KC: run in a Zammad test environment after copying kc/ into the app tree
# (kc/script/apply-overlay.sh, then cp -r kc/spec/. spec/):
#   bundle exec rspec spec/requests/kc/article_bcc_visibility_spec.rb

require 'rails_helper'

RSpec.describe 'KC article Bcc visibility', type: :request do
  let(:group)    { create(:group) }
  let(:agent)    { create(:agent, groups: [group]) }
  let(:customer) { create(:customer) }
  let(:ticket)   { create(:ticket, group: group, customer: customer) }
  let(:article) do
    create(:ticket_article, :outbound_email, ticket: ticket, internal: false,
                            to: customer.email, bcc: 'hidden@example.com')
  end

  it 'shows Bcc to agents' do
    authenticated_as(agent)
    get "/api/v1/ticket_articles/#{article.id}", as: :json

    expect(json_response['bcc']).to eq('hidden@example.com')
  end

  it 'hides Bcc from the customer', :aggregate_failures do
    authenticated_as(customer)
    get "/api/v1/ticket_articles/#{article.id}", as: :json
    expect(response).to have_http_status(:ok)
    expect(json_response).not_to have_key('bcc')

    get "/api/v1/ticket_articles/by_ticket/#{ticket.id}", as: :json
    expect(json_response.map { |a| a.key?('bcc') }).to all(be(false))
  end
end
