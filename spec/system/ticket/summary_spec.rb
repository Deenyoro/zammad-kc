# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'Ticket Summary', authenticated_as: :authenticate, type: :system do
  let(:agent)                        { create(:agent, groups: [ticket.group]) }
  let(:ticket)                       { create(:ticket) }
  let(:article)                      { create(:ticket_article, ticket:) }
  let(:ai_provider)                  { 'zammad_ai' }
  let(:ai_assistance_ticket_summary) { true }

  def authenticate
    Setting.set('ai_provider', ai_provider)
    Setting.set('ai_assistance_ticket_summary', ai_assistance_ticket_summary)

    article

    agent
  end

  before do
    if defined?(initial_cache_key)
      allow(AI::Service::TicketSummarize)
        .to receive(:cache_key).and_return(initial_cache_key, :noop, updated_cache_key)

      Rails.cache.write(initial_cache_key, { 'summary' => initial_summary })
      Rails.cache.write(updated_cache_key, { 'summary' => updated_summary })

      allow_any_instance_of(Service::Ticket::AIAssistance::Summarize)
        .to receive(:execute).and_return({ 'summary' => updated_summary })
    end

    visit "ticket/zoom/#{ticket.id}"
  end

  describe 'Sidebar' do
    context 'when ai_provider is set' do
      let(:initial_summary) { Faker::Lorem.sentence }
      let(:updated_summary)   { Faker::Lorem.sentence }
      let(:initial_cache_key) { "ticket_summary_#{ticket.id}" }
      let(:updated_cache_key) { "ticket_summary_#{ticket.id}_2" }

      it 'displays and updates summary in sidebar', performs_jobs: true do
        click '.tabsSidebar-tab[data-tab=summary]'

        expect(page).to have_text 'CONVERSATION SUMMARY'
        expect(page).to have_text initial_summary

        create(:ticket_article, ticket:)

        expect(page).to have_text 'generating the summary for you'

        perform_enqueued_jobs(only: TicketAIAssistanceSummarizeJob)

        expect(page).to have_text updated_summary
      end
    end

    context 'when summary feature is disabled' do
      let(:ai_assistance_ticket_summary) { false }

      it 'does not show sidebar' do
        expect(page).to have_text(ticket.title)
        expect(page).to have_no_css('.tabsSidebar-tab[data-tab=summary]')
      end
    end
  end

  describe 'Banner' do
    context 'when ai_provider is set' do
      it 'displays Summary banner and opens sidebar' do
        expect(page).to have_text('has prepared a summary of this ticket.')

        click_on('See Summary')

        expect(page).to have_css('.js-headline', text: 'Summary')
      end

      it 'allows to hide Summary banner' do
        click_on('Hide')

        in_modal do
          click '.js-submit'
        end

        expect(page).to have_no_text('has prepared a summary of this ticket.')

        expect(agent.reload.preferences).to include(ticket_summary_banner_hidden: be_truthy)
      end
    end
  end
end
