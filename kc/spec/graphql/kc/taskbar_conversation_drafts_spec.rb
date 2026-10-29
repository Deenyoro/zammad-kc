# KC: run in a Zammad test environment after copying kc/ into the app tree
# (kc/script/apply-overlay.sh, then cp -r kc/spec/. spec/):
#   bundle exec rspec spec/graphql/kc/taskbar_conversation_drafts_spec.rb
#
# The KC new-conversation drafts (Kc::TaskbarConversationDraftEntities) are
# taskbar items of the new desktop UI like the ticket create screen: listed,
# stored and pushed through the upstream taskbar GraphQL API.

require 'rails_helper'

RSpec.describe 'KC conversation draft taskbar items', authenticated_as: :agent, type: :graphql do
  let(:agent) { create(:agent) }
  let(:state) do
    {
      'phone_number' => '+15555550111',
      'customer_id'  => '',
      'channel_id'   => '3',
      'group_id'     => '',
      'body'         => 'Hello there',
      'skip_send'    => false,
    }
  end
  let(:draft) do
    create(:taskbar, user_id: agent.id, app: 'desktop', key: 'KcNewSmsScreen-4711',
                     callback: 'KcNewSmsConversationContent', params: { id: '4711' }, state: state)
  end

  describe 'userCurrentTaskbarItemList' do
    let(:query) do
      <<~QUERY
        query userCurrentTaskbarItemList($app: EnumTaskbarApp) {
          userCurrentTaskbarItemList(app: $app) {
            key
            callback
            state
            params
            entity {
              __typename
            }
            entityAccess
            changed
          }
        }
      QUERY
    end

    it 'serializes a draft item', :aggregate_failures do
      draft
      gql.execute(query, variables: { app: 'desktop' })

      item = gql.result.data.find { |entry| entry['key'] == 'KcNewSmsScreen-4711' }
      expect(item).to include(
        'callback'     => 'KcNewSmsConversationContent',
        'params'       => { 'id' => '4711' },
        'entity'       => nil,
        'entityAccess' => nil,
        'changed'      => true,
      )
      expect(item['state']).to include('phone_number' => '+15555550111', 'body' => 'Hello there')
    end

    it 'serializes the FreePBX and Teams drafts too' do
      create(:taskbar, user_id: agent.id, app: 'desktop', key: 'KcNewFreepbxSmsScreen-1',
                       callback: 'KcNewFreepbxSmsConversationContent', params: { id: '1' })
      create(:taskbar, user_id: agent.id, app: 'desktop', key: 'KcNewTeamsScreen-2',
                       callback: 'KcNewTeamsConversationContent', params: { id: '2' })
      gql.execute(query, variables: { app: 'desktop' })

      expect(gql.result.data.pluck('callback')).to contain_exactly('KcNewFreepbxSmsConversationContent', 'KcNewTeamsConversationContent')
    end
  end

  describe 'userCurrentTaskbarItemAdd and userCurrentTaskbarItemUpdate' do
    let(:add_query) do
      <<~QUERY
        mutation userCurrentTaskbarItemAdd($input: UserTaskbarItemInput!) {
          userCurrentTaskbarItemAdd(input: $input) {
            taskbarItem {
              id
              key
              callback
            }
            errors {
              message
            }
          }
        }
      QUERY
    end
    let(:update_query) do
      <<~QUERY
        mutation userCurrentTaskbarItemUpdate($id: ID!, $input: UserTaskbarItemInput!) {
          userCurrentTaskbarItemUpdate(id: $id, input: $input) {
            taskbarItem {
              key
              dirty
            }
            errors {
              message
            }
          }
        }
      QUERY
    end
    let(:input) do
      {
        app:      'desktop',
        callback: 'KcNewTeamsConversationContent',
        key:      'KcNewTeamsScreen-6c0e2b1a-1f7d-4f1e-8d5c-0a9b8c7d6e5f',
        notify:   false,
        params:   { id: '6c0e2b1a-1f7d-4f1e-8d5c-0a9b8c7d6e5f' },
        prio:     1,
      }
    end

    it 'creates a draft tab and stores its state the way the legacy UI reads it', :aggregate_failures do
      gql.execute(add_query, variables: { input: input })
      expect(gql.result.data[:taskbarItem]).to include('callback' => 'KcNewTeamsConversationContent')

      taskbar = Taskbar.find_by!(user_id: agent.id, key: input[:key])
      teams_state = { 'teams_user_id' => 'aad-1', 'display_name' => 'Jane Doe', 'email' => 'jane@example.com',
                      'channel_id' => '2', 'group_id' => '', 'body' => 'Hi', 'skip_send' => false }

      gql.execute(update_query, variables: { id: gql.id(taskbar), input: input.merge(state: teams_state, dirty: true) })
      expect(gql.result.data[:taskbarItem]).to include('dirty' => true)

      expect(taskbar.reload.state.to_h).to eq(teams_state)
      expect(taskbar.callback).to eq('KcNewTeamsConversationContent')
      expect(taskbar.params.to_h).to eq('id' => '6c0e2b1a-1f7d-4f1e-8d5c-0a9b8c7d6e5f')
    end
  end

  describe 'userCurrentTaskbarItemUpdates' do
    let(:mock_channel) { build_mock_channel }
    let(:subscription) do
      <<~QUERY
        subscription userCurrentTaskbarItemUpdates($app: EnumTaskbarApp!) {
          userCurrentTaskbarItemUpdates(app: $app) {
            addItem {
              key
              callback
            }
            updateItem {
              key
              callback
            }
            removeItem
          }
        }
      QUERY
    end

    def broadcasts
      mock_channel.mock_broadcasted_messages.pluck(:result)
    end

    before do
      gql.execute(subscription, variables: { app: 'desktop' }, context: { channel: mock_channel })
    end

    # Before, these pushes failed to serialize - the callback was no enum value -
    #   and KC kept them from the new UI (Kc::TaskbarLegacyOnlyTabs).
    it 'pushes created, updated and removed drafts', :aggregate_failures do
      taskbar = draft
      taskbar.update!(state: state.merge('body' => 'Changed'))
      gid = Gql::ZammadSchema.id_from_object(taskbar)
      taskbar.destroy!

      expect(broadcasts.pluck('errors').compact).to be_empty

      updates = broadcasts.map { |result| result['data']['userCurrentTaskbarItemUpdates'] }
      expect(updates).to eq(
        [
          { 'addItem' => { 'key' => 'KcNewSmsScreen-4711', 'callback' => 'KcNewSmsConversationContent' }, 'updateItem' => nil, 'removeItem' => nil },
          { 'addItem' => nil, 'updateItem' => { 'key' => 'KcNewSmsScreen-4711', 'callback' => 'KcNewSmsConversationContent' }, 'removeItem' => nil },
          { 'addItem' => nil, 'updateItem' => nil, 'removeItem' => gid },
        ]
      )
    end
  end
end
