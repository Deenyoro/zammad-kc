# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'AI Assistance Text Tools', authenticated_as: :authenticate, type: :system do
  let(:agent)                    { create(:agent) }
  let(:ai_provider)              { 'zammad_ai' }
  let(:ai_assistance_text_tools) { true }
  let(:input)                    { 'Teh qwik braun foxx jumpz ova da laizi doge.' }
  let(:output)                   { 'The quick brown fox jumps over the lazy dog.' }

  def authenticate
    Setting.set('ai_provider', ai_provider)
    Setting.set('ai_assistance_text_tools', ai_assistance_text_tools)

    agent
  end

  before do
    allow_any_instance_of(AI::Service::TextSpellingAndGrammar).to receive(:execute).and_return(output)
  end

  context 'when using ticket create' do
    before do
      visit 'ticket/create'
    end

    it 'shows text tools action and replaces selected text' do
      set_editor_field_value('body', input)
      send_keys([magic_key, 'a'])

      expect(page).to have_no_css('[role=menu]')

      click_on 'Smart Editor'

      expect(page).to have_css('[role=menu]')

      find('.js-action', text: 'Fix spelling and grammar').click

      expect(page).to have_no_css('[role=menu]')
      check_editor_field_value('body', output)
    end

    context 'when text tools are disabled' do
      let(:ai_assistance_text_tools) { false }

      it 'does not show text tools action' do
        expect(page).to have_no_text('Smart Editor')
      end
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

    it 'shows text tools action and replaces selected text' do
      find('.articleNewEdit-body').send_keys(input)
      send_keys([magic_key, 'a'])

      expect(page).to have_no_css('[role=menu]')

      click_on 'Smart Editor'

      expect(page).to have_css('[role=menu]')

      find('.js-action', text: 'Fix spelling and grammar').click

      expect(page).to have_no_css('[role=menu]')
      expect(find('.articleNewEdit-body').text).to eq(output)
    end

    context 'when text tools are disabled' do
      let(:ai_assistance_text_tools) { false }

      it 'does not show text tools action' do
        expect(page).to have_text(ticket.title).and have_no_text('Smart Editor')
      end
    end
  end
end
