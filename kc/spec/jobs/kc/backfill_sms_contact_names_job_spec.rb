# KC: run in a Zammad test environment after copying kc/ into the app tree
# (kc/script/apply-overlay.sh, then cp -r kc/spec/. spec/):
#   bundle exec rspec spec/jobs/kc/backfill_sms_contact_names_job_spec.rb

require 'rails_helper'

RSpec.describe Kc::BackfillSmsContactNamesJob do
  let(:number)         { '+14125550100' }
  let(:customer)       { create(:customer, firstname: number, lastname: '', email: '', phone: number) }
  let(:sms_prefs)      { { ringcentral_sms: { from_phone: number, participants: [number], channel_id: 1 } } }
  let!(:open_ticket)   { create(:ticket, title: "SMS from #{number}", customer: customer, state_name: 'open', preferences: sms_prefs) }
  let!(:closed_ticket) { create(:ticket, title: "SMS from #{number}", customer: customer, state_name: 'closed', preferences: sms_prefs) }

  before do
    allow(Kc::PhoneContacts).to receive_messages(ringcentral_book: { '4125550100' => 'Jane Smith' }, freepbx_book: {})
  end

  it 'names open SMS tickets and their placeholder customer', :aggregate_failures do
    described_class.new.perform
    expect(open_ticket.reload.title).to eq("SMS from Jane Smith (#{number})")
    expect(customer.reload).to have_attributes(firstname: 'Jane', lastname: 'Smith')
  end

  it 'leaves closed tickets alone' do
    expect { described_class.new.perform }.not_to change { closed_ticket.reload.title }
  end

  it 'changes nothing in a dry run', :aggregate_failures do
    report = described_class.new.perform(dry_run: true)
    expect(report[:would_update]).to eq(1)
    expect(open_ticket.reload.title).to eq("SMS from #{number}")
  end
end
