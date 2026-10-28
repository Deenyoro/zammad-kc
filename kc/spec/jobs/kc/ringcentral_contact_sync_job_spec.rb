# KC: run in a Zammad test environment after copying kc/ into the app tree
# (kc/script/apply-overlay.sh, then cp -r kc/spec/. spec/):
#   bundle exec rspec spec/jobs/kc/ringcentral_contact_sync_job_spec.rb

require 'rails_helper'

RSpec.describe Kc::RingcentralContactSyncJob do
  let!(:enabled) do
    create(:channel, area: 'RingCentralSms::Account', options: { contact_import: true, contact_export: false })
  end
  let!(:disabled) do
    create(:channel, area: 'RingCentralSms::Account', options: { contact_import: false, contact_export: false })
  end
  let!(:inactive) do
    create(:channel, area: 'RingCentralSms::Account', active: false, options: { contact_import: true })
  end
  let(:ran) { [] }

  before do
    allow_any_instance_of(Kc::RingcentralContactSync).to receive(:run) do |sync|
      ran << sync.channel.id
      { status: 'completed' }
    end
  end

  it 'syncs only active channels with a direction turned on' do
    described_class.perform_now
    expect(ran & [enabled.id, disabled.id, inactive.id]).to eq([enabled.id])
  end

  it 'runs one channel when given its id' do
    described_class.perform_now(disabled.id)
    expect(ran).to be_empty
  end
end
