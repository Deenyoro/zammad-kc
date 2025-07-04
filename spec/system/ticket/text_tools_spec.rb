# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'AI Assistance Text Tools', authenticated_as: :authenticate, type: :system do
  let(:agent)                    { create(:agent) }
  let(:ai_provider)              { 'zammad_ai' }
  let(:ai_assistance_text_tools) { true }
  let(:input)                    { 'Teh qwik braun foxx jumpz ova da laizi doge.' }
  let(:output)                   { Struct.new(:content, :stored_result, :fresh, keyword_init: true).new(content: 'The quick brown fox jumps over the lazy dog.', stored_result: nil, fresh: false) }

  def authenticate
    Setting.set('ai_provider', ai_provider)
    Setting.set('ai_assistance_text_tools', ai_assistance_text_tools)

    agent
  end

  before do
    allow_any_instance_of(AI::Service::TextSpellingAndGrammar).to receive(:execute).and_return(output)
  end

  shared_examples 'showing text tools dropdown and replacing selected text' do
    before do
      skip('does not work with chrome driver') if Capybara.current_driver == :zammad_chrome
    end

    it 'shows text tools dropdown and replaces selected text' do
      set_editor_field_value('body', input)

      # Wait for the taskbar update to finish.
      taskbar_timestamp = Taskbar.last.updated_at
      wait.until { Taskbar.last.updated_at != taskbar_timestamp }

      find("[data-name='body']").send_keys([magic_key, 'a'])

      expect(page).to have_css('[role=menu]')

      find('.js-action', text: 'Fix spelling and grammar').click

      in_modal do
        expect(page).to have_css('h1', text: 'Writing Assistant: Fix spelling and grammar')
        expect(page).to have_text(input).and have_text(output[:content])

        click_on 'Approve'
      end

      check_editor_field_value('body', output[:content])
    end
  end

  shared_examples 'not showing text tools dropdown' do
    it 'does not show text tools dropdown' do
      set_editor_field_value('body', input)

      # Wait for the taskbar update to finish.
      taskbar_timestamp = Taskbar.last.updated_at
      wait.until { Taskbar.last.updated_at != taskbar_timestamp }

      find("[data-name='body']").send_keys([magic_key, 'a'])

      expect(page).to have_no_css('[role=menu]')
    end
  end

  context 'when using ticket create' do
    before do
      visit 'ticket/create'
    end

    it_behaves_like 'showing text tools dropdown and replacing selected text'

    context 'when text tools are disabled' do
      let(:ai_assistance_text_tools) { false }

      it_behaves_like 'not showing text tools dropdown'
    end
  end

  context 'when using ticket zoom' do
    let(:agent)   { create(:agent, groups: [ticket.group]) }
    let(:ticket)  { create(:ticket) }
    let(:article) { create(:ticket_article, ticket:) }

    before do
      article

      visit "ticket/zoom/#{ticket.id}"

      find('.article-new').click

      # Wait till input box expands completely.
      find('.attachmentPlaceholder-label').in_fixed_position
    end

    it_behaves_like 'showing text tools dropdown and replacing selected text'

    context 'when text tools are disabled' do
      let(:ai_assistance_text_tools) { false }

      it_behaves_like 'not showing text tools dropdown'
    end
  end
end
