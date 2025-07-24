# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'Ticket Summary', authenticated_as: :authenticate, type: :system do
  let(:agent)                        { create(:agent, groups: [ticket.group]) }
  let(:ticket)                       { create(:ticket) }
  let(:article)                      { create(:ticket_article, ticket:) }
  let(:ai_provider)                  { 'zammad_ai' }
  let(:ai_assistance_ticket_summary) { true }
  let(:checklist)                    { true }
  let(:initial_summary)              { "initial #{Faker::Lorem.unique.sentence}" }
  let(:updated_summary)              { "updated #{Faker::Lorem.unique.sentence}" }
  let(:initial_cache_key)            { "ticket_summary_#{ticket.id}" }
  let(:updated_cache_key)            { "ticket_summary_#{ticket.id}_2" }
  let(:ticket_summary_generation)    { 'on_ticket_detail_opening' }

  def authenticate
    Setting.set('ai_provider', ai_provider)
    Setting.set('ai_assistance_ticket_summary', ai_assistance_ticket_summary)
    Setting.set('checklist', checklist)
    Setting.set('ai_assistance_ticket_summary_config', {
                  open_questions: true,
                  suggestions:    true,
                  generate_on:    ticket_summary_generation
                })

    article

    agent
  end

  before do
    if defined?(initial_cache_key)
      initial_content = {
        'summary'     => initial_summary,
        'suggestions' => (initial_suggestions if defined?(initial_suggestions))
      }

      AI::StoredResult.create!(
        content: initial_content,
        version: AI::Service::TicketSummarize.persistent_version({ ticket: }, Locale.find_by(locale: agent.locale)),
        **AI::Service::TicketSummarize.persistent_lookup_attributes({ ticket: }, Locale.find_by(locale: agent.locale)),
      )

      updated_content = {
        'summary'     => updated_summary,
        'suggestions' => (updated_suggestions if defined?(updated_suggestions))
      }.compact

      allow_any_instance_of(AI::Service::TicketSummarize)
        .to receive(:ask_provider).and_return(updated_content)
    end
  end

  describe 'Sidebar' do
    before { visit "ticket/zoom/#{ticket.id}" }

    context 'when ai_provider is set' do
      before do
        click '.tabsSidebar-tab[data-tab=summary]'
      end

      it 'displays and updates summary in sidebar', performs_jobs: true do
        within '.sidebar[data-tab="summary"]' do
          expect(page).to have_text 'Conversation Summary'
          expect(page).to have_text initial_summary
        end

        create(:ticket_article, ticket:)

        # This will wait for the job to be enqueued.
        expect(page).to have_text 'generating the summary for you'

        perform_enqueued_jobs(only: TicketAIAssistanceSummarizeJob)

        within '.sidebar[data-tab="summary"]' do
          expect(page).to have_text updated_summary
        end
      end

      context 'when suggestions are available' do
        let(:initial_suggestions) do
          [
            Faker::Lorem.unique.sentence,
            Faker::Lorem.unique.sentence,
            Faker::Lorem.unique.sentence,
          ]
        end

        it 'shows add buttons' do
          within '.sidebar[data-tab="summary"]' do
            expect(page).to have_text 'Suggested Next Steps'
            expect(find_all('button[aria-label="Add as checklist item"]').length).to eq(3)
            expect(page).to have_button 'Add all to checklist'

            # Create the checklist & add the first item
            find_all('button[aria-label="Add as checklist item"]').first.click
          end

          expect(page).to have_text 'Checklist item successfully added.'

          within '.sidebar[data-tab="summary"]' do
            # Add to an existing checklist
            find_all('button[aria-label="Add as checklist item"]')[1].click
          end

          expect(page).to have_text 'Checklist item successfully added.'

          within '.sidebar[data-tab="summary"]' do
            click_on 'Add all to checklist'
          end

          within '.sidebar[data-tab="checklist"]' do
            expect(page).to have_text 'Checklist'
            expect(find_all('table tbody tr').length).to eq(5)
          end
        end

        context 'with checklist feature disabled' do
          let(:checklist) { false }

          it 'does not show add buttons' do
            within '.sidebar[data-tab="summary"]' do
              expect(page).to have_text 'Suggested Next Steps'
              expect(page).to have_no_button 'Add'
              expect(page).to have_no_button 'Add all to checklist'
            end
          end
        end
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

  describe 'Dot', performs_jobs: true do
    before { visit "ticket/zoom/#{ticket.id}" }

    context 'when summary was updated before opening the tab' do
      it 'dot is visible but gone after looking at the sidebar' do
        expect(page).to have_css('.tabsSidebar-tab[data-tab=summary] .tabsSidebar-tab-dot')

        click '.tabsSidebar-tab[data-tab=summary]'

        expect(page).to have_no_css('.tabsSidebar-tab[data-tab=summary] .tabsSidebar-tab-dot')

        refresh

        expect(page).to have_no_css('.tabsSidebar-tab[data-tab=summary] .tabsSidebar-tab-dot')
      end

      it 'dot is visible when summary is updated while looking at other tab' do
        click '.tabsSidebar-tab[data-tab=summary]'
        click '.tabsSidebar-tab[data-tab=customer]'

        create(:ticket_article, ticket:)

        expect(page).to have_no_css('.tabsSidebar-tab[data-tab=summary] .tabsSidebar-tab-dot')

        wait.until do
          enqueued_jobs.any? { |job| job[:job] == TicketAIAssistanceSummarizeJob }
        end

        perform_enqueued_jobs(only: TicketAIAssistanceSummarizeJob)

        expect(page).to have_css('.tabsSidebar-tab[data-tab=summary] .tabsSidebar-tab-dot')
      end

      it 'dot is not visible when summary is updated while looking at the summary tab' do
        click '.tabsSidebar-tab[data-tab=summary]'

        create(:ticket_article, ticket:)

        expect(page).to have_no_css('.tabsSidebar-tab[data-tab=summary] .tabsSidebar-tab-dot')

        wait.until do
          enqueued_jobs.any? { |job| job[:job] == TicketAIAssistanceSummarizeJob }
        end

        perform_enqueued_jobs(only: TicketAIAssistanceSummarizeJob)

        within '.sidebar[data-tab="summary"]' do
          expect(page).to have_text updated_summary
        end

        expect(page).to have_no_css('.tabsSidebar-tab[data-tab=summary] .tabsSidebar-tab-dot')
      end

      it 'dot is not visible when summary is updated by myself' do
        click '.tabsSidebar-tab[data-tab=summary]'
        click '.tabsSidebar-tab[data-tab=customer]'

        create(:ticket_article, ticket:, origin_by: agent)

        expect(page).to have_no_css('.tabsSidebar-tab[data-tab=summary] .tabsSidebar-tab-dot')

        wait.until do
          enqueued_jobs.any? { |job| job[:job] == TicketAIAssistanceSummarizeJob }
        end

        perform_enqueued_jobs(only: TicketAIAssistanceSummarizeJob)

        expect(page).to have_no_css('.tabsSidebar-tab[data-tab=summary] .tabsSidebar-tab-dot')

        click '.tabsSidebar-tab[data-tab=summary]'
        within '.sidebar[data-tab="summary"]' do
          expect(page).to have_text updated_summary
        end

        expect(page).to have_no_css('.tabsSidebar-tab[data-tab=summary] .tabsSidebar-tab-dot')
      end
    end
  end

  describe 'Requesting a summary' do
    let(:other_ticket) { create(:ticket, group: ticket.group) }

    context 'when requesting on opening a ticket' do
      it 'makes a request for a summary on opening a ticket' do
        # Create multiple taskbars
        visit "ticket/zoom/#{ticket.id}"
        visit "ticket/zoom/#{other_ticket.id}"

        visit '#dashboard'

        # Reload the app to ensure the summary subscriptions are not set up
        refresh

        allow(Service::Ticket::AIAssistance::Summarize).to receive(:new).and_call_original

        visit "ticket/zoom/#{ticket.id}"

        within :active_content do
          expect(page).to have_text ticket.title
        end

        # Expect exactly once, this checks if non-active taskbar is not subscribing on app load
        expect(Service::Ticket::AIAssistance::Summarize).to have_received(:new).once
      end
    end

    context 'when requesting on opening a sidebar' do
      let(:ticket_summary_generation) { 'on_ticket_summary_sidebar_activation' }

      it 'makes a request for a summary on clicking on sidebar' do
        visit '#dashboard'

        allow(Service::Ticket::AIAssistance::Summarize).to receive(:new).and_call_original

        visit "ticket/zoom/#{ticket.id}"

        expect(page).to have_text ticket.title

        expect(Service::Ticket::AIAssistance::Summarize).not_to have_received(:new)

        click '.tabsSidebar-tab[data-tab=summary]'

        expect(Service::Ticket::AIAssistance::Summarize).to have_received(:new).once
      end
    end

    context 'when group generation setting is configured' do
      let(:ticket_summary_generation) { 'on_ticket_detail_opening' }

      before do
        ticket.group.update!(summary_generation: 'on_ticket_summary_sidebar_activation')
      end

      it 'uses the group setting over the default' do
        visit '#dashboard'

        allow(Service::Ticket::AIAssistance::Summarize).to receive(:new).and_call_original

        visit "ticket/zoom/#{ticket.id}"

        expect(page).to have_text ticket.title

        expect(Service::Ticket::AIAssistance::Summarize).not_to have_received(:new)

        click '.tabsSidebar-tab[data-tab=summary]'

        expect(Service::Ticket::AIAssistance::Summarize).to have_received(:new).once
      end
    end
  end
end
