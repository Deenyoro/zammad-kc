# KC: run in a Zammad test environment after copying kc/ into the app tree
# (kc/script/apply-overlay.sh, then cp -r kc/spec/. spec/):
#   bundle exec rspec spec/models/kc/taskbar_conversation_draft_entities_spec.rb

require 'rails_helper'

RSpec.describe Kc::TaskbarConversationDraftEntities do
  let(:callbacks) { %w[KcNewSmsConversationContent KcNewFreepbxSmsConversationContent KcNewTeamsConversationContent] }

  it 'is prepended onto the Taskbar singleton class' do
    expect(Taskbar.singleton_class.ancestors).to include(described_class)
  end

  it 'adds the draft callbacks to the taskbar entities and keeps the upstream ones' do
    expect(Taskbar.taskbar_entities).to include(*callbacks, 'TicketZoom', 'TicketCreate', 'Search')
  end

  it 'lists the draft callbacks once' do
    expect(Taskbar.taskbar_entities.tally.values).to all(eq(1))
  end

  it 'makes the draft callbacks values of the GraphQL TaskbarEntityType enum' do
    expect(Gql::Types::Enum::TaskbarEntityType.values.keys).to include(*callbacks, 'TicketZoom')
  end

  it 'is no longer kept from the new UI by Kc::TaskbarLegacyOnlyTabs' do
    expect('Kc::TaskbarLegacyOnlyTabs'.safe_constantize).to be_nil
  end

  describe '.draft_key?' do
    it 'accepts the keys of the three drafts', :aggregate_failures do
      expect(described_class.draft_key?('KcNewSmsScreen-12345')).to be(true)
      expect(described_class.draft_key?('KcNewFreepbxSmsScreen-3f1c9a2e-8b7d-4c6e-9f0a-1b2c3d4e5f60')).to be(true)
      expect(described_class.draft_key?('KcNewTeamsScreen-7')).to be(true)
    end

    it 'refuses other keys', :aggregate_failures do
      expect(described_class.draft_key?('KcNewSmsScreen')).to be(false)
      expect(described_class.draft_key?('KcNewSmsScreen-')).to be(false)
      expect(described_class.draft_key?('TicketCreateScreen-1')).to be(false)
      expect(described_class.draft_key?('Ticket-1')).to be(false)
      expect(described_class.draft_key?(nil)).to be(false)
    end
  end

  describe 'TaskbarPolicy::Scope' do
    let(:agent) { create(:agent) }

    it 'lists draft tabs of the user, as the new desktop UI does' do
      draft = create(:taskbar, user_id: agent.id, app: 'desktop', key: 'KcNewSmsScreen-1',
                               callback: 'KcNewSmsConversationContent', params: { id: '1' })

      expect(TaskbarPolicy::Scope.new(agent, Taskbar).resolve).to include(draft)
    end
  end
end
