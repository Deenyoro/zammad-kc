# KC: run in a Zammad test environment after copying kc/ into the app tree
# (kc/script/apply-overlay.sh, then cp -r kc/spec/. spec/):
#   bundle exec rspec spec/models/kc/taskbar_legacy_only_tabs_spec.rb

require 'rails_helper'

RSpec.describe Kc::TaskbarLegacyOnlyTabs do
  let(:user) { create(:agent) }

  before do
    allow(Gql::Subscriptions::User::Current::TaskbarItemUpdates).to receive(:trigger_after_create)
    allow(Gql::Subscriptions::User::Current::TaskbarItemUpdates).to receive(:trigger_after_update)
    allow(Gql::Subscriptions::User::Current::TaskbarItemUpdates).to receive(:trigger_after_destroy)
  end

  def tab(callback, key)
    UserInfo.current_user_id = user.id
    Taskbar.create!(user: user, app: 'desktop', key: key, callback: callback,
                    params: { id: '1' }, state: {}, prio: 1, notify: false)
  end

  it 'is prepended into Taskbar' do
    expect(Taskbar.ancestors).to include(described_class)
  end

  it 'keeps KC draft tabs out of the new UI taskbar subscriptions', :aggregate_failures do
    taskbar = tab('KcNewSmsConversationContent', 'KcNewSmsScreen-1')
    taskbar.update!(state: { body: 'hi' }, params: { id: '1', title: 'SMS' })
    taskbar.destroy!

    expect(Gql::Subscriptions::User::Current::TaskbarItemUpdates).not_to have_received(:trigger_after_create)
    expect(Gql::Subscriptions::User::Current::TaskbarItemUpdates).not_to have_received(:trigger_after_update)
    expect(Gql::Subscriptions::User::Current::TaskbarItemUpdates).not_to have_received(:trigger_after_destroy)
  end

  it 'still notifies the new UI about ticket tabs' do
    tab('TicketCreate', 'TicketCreateScreen-1')

    expect(Gql::Subscriptions::User::Current::TaskbarItemUpdates).to have_received(:trigger_after_create)
  end
end
