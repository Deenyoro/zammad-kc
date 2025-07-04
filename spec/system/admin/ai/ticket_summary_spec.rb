# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'Manage > AI > Ticket Summary', type: :system do

  context 'with ticket summary service options', authenticated_as: :admin do
    let(:admin) { create(:admin) }

    before { visit '/#ai/ticket_summary' }

    it 'displays the ticket summary service options and can change them' do
      within(:active_content) do
        # Find and click the suggestions checkbox by its label text
        find('label', text: 'Suggested Next Steps').click
        find('label', text: 'Open Questions').click
      end

      expect(Setting.get('ai_assistance_ticket_summary_config')).to eq({
                                                                         'open_questions' => false,
                                                                         'suggestions'    => true, # by default feature was not enabled
                                                                       })
    end

    context 'without provider configured' do
      before do
        Setting.set('ai_provider', '')
        visit '/#ai/ticket_summary'
      end

      it 'displays a warning when summary is enabled' do
        within(:active_content) do
          click '.js-aiAssistanceTicketSummarySetting'

          expect(page).to have_css('.alert--warning')
        end
      end
    end
  end
end
