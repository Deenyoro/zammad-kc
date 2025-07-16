# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'
require 'system/examples/pagination_examples'

RSpec.describe 'AI > AI Agents', type: :system do
  context 'when ajax pagination' do
    include_examples 'pagination', model: :ai_agent, klass: AI::Agent, path: 'ai/ai_agents'
  end

  context 'when no AI provider is configured' do
    it 'shows a warning message' do
      visit '#ai/ai_agents'

      expect(page).to have_text('The provider configuration is missing. Please set up the provider before proceeding in AI > Provider.')
    end
  end

  context 'when AI provider is configured' do
    before do
      Setting.set('ai_provider', 'open_ai')
      Setting.set('ai_provider_config', {
                    token: ENV['OPEN_AI_TOKEN'],
                  })

      ai_agent = create(:ai_agent, name: 'Test Agent')
      create(:trigger, perform: { 'ai.ai_agent' => { 'ai_agent_id' => ai_agent.id } })
      create(:job, perform: { 'ai.ai_agent' => { 'ai_agent_id' => ai_agent.id } })
    end

    it 'shows AI agents in the UI' do
      visit '#ai/ai_agents'

      expect(page).to have_text('Test Agent')
    end

    context 'with references' do
      # AI agent #1: one job, multiple triggers
      let(:ai_agent_1) { create(:ai_agent, name: 'AI Agent 1') }

      # AI agent #2: multiple job, one trigger
      let(:ai_agent_2) { create(:ai_agent, name: 'AI Agent 2') }

      # AI agent #3: no references
      let(:ai_agent_3) { create(:ai_agent, name: 'AI Agent 3') }

      before do
        create(:trigger, name: 'Trigger1 Group Dispatcher 1', perform: { 'ai.ai_agent' => { 'ai_agent_id' => ai_agent_1.id } })
        create(:trigger, name: 'Trigger1 Group Dispatcher 2', perform: { 'ai.ai_agent' => { 'ai_agent_id' => ai_agent_1.id } })
        create(:job,     name: 'Job1 Group Dispatcher 1',     perform: { 'ai.ai_agent' => { 'ai_agent_id' => ai_agent_1.id } })

        create(:trigger, name: 'Trigger2 Group Dispatcher 1', perform: { 'ai.ai_agent' => { 'ai_agent_id' => ai_agent_2.id } })
        create(:job,     name: 'Job2 Group Dispatcher 1',     perform: { 'ai.ai_agent' => { 'ai_agent_id' => ai_agent_2.id } })
        create(:job,     name: 'Job2 Group Dispatcher 2',     perform: { 'ai.ai_agent' => { 'ai_agent_id' => ai_agent_2.id } })

        ai_agent_3
      end

      it 'shows AI agent with correct references' do
        visit '#ai/ai_agents'

        within ".js-tableBody tr.item[data-id='#{ai_agent_1.id}']" do
          expect(page).to have_text('AI Agent 1')
          expect(page).to have_text('2 triggers')
          expect(page).to have_text('Job1 Group Dispatcher 1')
        end

        within ".js-tableBody tr.item[data-id='#{ai_agent_2.id}']" do
          expect(page).to have_text('AI Agent 2')
          expect(page).to have_text('Trigger2 Group Dispatcher 1')
          expect(page).to have_text('2 schedulers')
        end

        within ".js-tableBody tr.item[data-id='#{ai_agent_3.id}']" do
          expect(page).to have_text('AI Agent 3')
          expect(page).to have_text('Unused')

          # Test that badge is removed when references are added.
          create(:trigger, name: 'Trigger3 Group Dispatcher 1', perform: { 'ai.ai_agent' => { 'ai_agent_id' => ai_agent_3.id } })
          await_empty_ajax_queue
          expect(page).to have_text('Trigger3 Group Dispatcher 1')
          expect(page).to have_no_text('Unused')

          # Test that references text is updated when references are changed.
          Job.last.update!(perform: { 'ai.ai_agent' => { 'ai_agent_id' => ai_agent_3.id } })
          await_empty_ajax_queue
          expect(page).to have_text('Job2 Group Dispatcher 2')

          # Test that references are removed/badge is added when the last reference is deleted.
          Trigger.last.destroy!
          Job.last.destroy!
          await_empty_ajax_queue
          expect(page).to have_no_text('Trigger3 Group Dispatcher 1')
          expect(page).to have_text('Unused')
        end
      end
    end
  end
end
