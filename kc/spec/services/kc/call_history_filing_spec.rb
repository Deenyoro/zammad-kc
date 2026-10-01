# KC: run in a Zammad test environment after copying kc/ into the app tree
# (kc/script/apply-overlay.sh, then cp -r kc/spec/. spec/):
#   bundle exec rspec spec/services/kc/call_history_filing_spec.rb

require 'rails_helper'

RSpec.describe Kc::CallHistoryFiling do
  subject(:filer) { Class.new { include Kc::CallHistoryFiling }.new }

  let(:number)     { '+14125550100' }
  let(:call_start) { 10.minutes.ago.change(usec: 0) }
  let(:sms_prefs)  { { ringcentral_sms: { from_phone: number, participants: [number], channel_id: 1 } } }
  let(:ticket)     { create(:ticket, state_name: 'open', preferences: sms_prefs) }

  def note(key: 'rc_call:1', source: 'RingCentral', inbound: true, start: call_start)
    filer.note_call_on_sms_thread(
      dedup_key: key, external: number, inbound: inbound, start_time: start, duration: 75,
      outcome: 'Answered on RingCentral', line: "#{number} → +14125559999", source: source,
    )
  end

  def call_notes
    Ticket::Article.where(ticket_id: ticket.id).where('message_id LIKE ?', 'kc_call_note:%')
  end

  before do
    allow(Setting).to receive(:get).and_call_original
    allow(Setting).to receive(:get).with('kc_ringcentral_sms_call_thread_notes').and_return(true)
    allow(Kc::OutboundSms).to receive(:available_numbers).and_return([])
    ticket
  end

  it 'adds an internal note and leaves the ticket as it was', :aggregate_failures do
    expect { note }.not_to change { ticket.reload.attributes.slice('state_id', 'owner_id', 'pending_time') }
    expect(call_notes.sole).to have_attributes(internal: true, created_at: call_start)
    expect(call_notes.sole.sender.name).to eq('System')
    expect(call_notes.sole.body).to include('Inbound call via RingCentral', 'Duration: 1:15')
  end

  it 'writes one note when the same call is seen twice', :aggregate_failures do
    note
    expect(note).to eq(:unchanged)
    expect(call_notes.count).to eq(1)
  end

  it 'writes one note when the other system reports the same call' do
    note
    note(key: 'freepbx_call:1', source: 'FreePBX', start: call_start + 40.seconds)
    expect(call_notes.count).to eq(1)
  end

  it 'notes a different call from the other system' do
    note
    note(key: 'freepbx_call:2', source: 'FreePBX', inbound: false, start: call_start + 40.seconds)
    expect(call_notes.count).to eq(2)
  end

  it 'does nothing when the setting is off', :aggregate_failures do
    allow(Setting).to receive(:get).with('kc_ringcentral_sms_call_thread_notes').and_return(false)
    expect(note).to be_nil
    expect(call_notes).to be_empty
  end

  context 'when the thread was closed before the call' do
    let(:ticket) { create(:ticket, state_name: 'closed', preferences: sms_prefs, created_at: 2.days.ago, close_at: 1.day.ago) }

    it 'adds nothing', :aggregate_failures do
      expect(note).to be_nil
      expect(call_notes).to be_empty
    end
  end

  context 'when the thread was closed after the call started' do
    let(:ticket) { create(:ticket, state_name: 'open', preferences: sms_prefs, created_at: 1.hour.ago) }

    before { ticket.update!(state: Ticket::State.lookup(name: 'closed')) }

    it 'still gets the note and stays closed', :aggregate_failures do
      expect(note).to eq(:noted)
      expect(ticket.reload.state.name).to eq('closed')
    end
  end

  context 'when the thread was merged' do
    let(:ticket) { create(:ticket, state_name: 'merged', preferences: sms_prefs) }

    it 'adds nothing' do
      expect(note).to be_nil
    end
  end
end
