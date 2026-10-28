# KC: run in a Zammad test environment after copying kc/ into the app tree
# (kc/script/apply-overlay.sh, then cp -r kc/spec/. spec/):
#   bundle exec rspec spec/services/kc/ringcentral_contact_sync_spec.rb

require 'rails_helper'

RSpec.describe Kc::RingcentralContactSync do
  # An in-memory RingCentral address book standing in for the HTTP client.
  let(:fake_client_class) do
    Class.new do
      attr_reader :book, :created, :updated
      attr_accessor :failures

      def initialize(book)
        @book     = book
        @created  = []
        @updated  = []
        @failures = []
        @next_id  = 9000
      end

      def address_book_contacts(page: 1, per_page: 250)
        { 'records' => book.map(&:dup), 'paging' => { 'page' => page, 'totalPages' => 1 } }
      end

      def create_address_book_contact(attributes)
        raise failures.shift if failures.any?

        contact = attributes.stringify_keys.merge('id' => (@next_id += 1), 'uri' => 'x', 'availability' => 'Alive')
        book << contact
        created << contact
        contact
      end

      def update_address_book_contact(contact_id, attributes)
        raise failures.shift if failures.any?

        contact = book.find { |c| c['id'].to_s == contact_id.to_s }
        contact.replace(attributes.stringify_keys.merge('id' => contact['id']))
        updated << contact
        contact
      end
    end
  end

  let(:book)    { [] }
  let(:client)  { fake_client_class.new(book) }
  let(:import)  { true }
  let(:export)  { true }
  let(:channel) do
    create(:channel, area: 'RingCentralSms::Account',
                     options: { adapter: 'kc_ringcentral_sms', phone_number: '+14125550000',
                                contact_import: import, contact_export: export })
  end
  let(:sync) { described_class.new(channel) }

  before do
    allow(Kc::RingcentralApi).to receive(:with_channel_tokens).and_return(client)
    allow(sync).to receive(:pause)
  end

  def contact(id, attrs = {})
    { 'id' => id, 'uri' => "https://platform.ringcentral.com/contact/#{id}", 'availability' => 'Alive' }.merge(attrs.stringify_keys)
  end

  def directory_user(attrs = {})
    user = create(:customer, attrs)
    create(:authorization, provider: 'microsoft_teams', user: user, uid: SecureRandom.uuid)
    user
  end

  def state_of(user)
    user.reload.preferences[described_class::PREFERENCE_KEY][channel.id.to_s]
  end

  describe 'import' do
    let(:export) { false }

    it 'creates a customer for an unknown contact, linking an existing organization by exact name', :aggregate_failures do
      org = create(:organization, name: 'Acme Corp')
      book << contact(1, firstName: 'Jane', lastName: 'Smith', mobilePhone: '(412) 555-0101', company: 'Acme Corp', email: 'jane@example.com')

      expect { sync.run }.to change(User, :count).by(1)
      user = User.find_by(email: 'jane@example.com')
      expect(user).to have_attributes(firstname: 'Jane', lastname: 'Smith', mobile: '+14125550101', organization_id: org.id)
      expect(state_of(user)).to include('contact_id' => '1', 'origin' => 'import')
    end

    it 'never creates organizations' do
      book << contact(1, firstName: 'Jane', lastName: 'Smith', mobilePhone: '4125550101', company: 'New Company Inc')
      expect { sync.run }.not_to change(Organization, :count)
    end

    it 'matches by email before number', :aggregate_failures do
      by_email = create(:customer, firstname: 'Janet', lastname: 'S', email: 'jane@example.com')
      create(:customer, firstname: 'Other', lastname: 'Person', mobile: '+14125550101')
      book << contact(1, firstName: 'Jane', lastName: 'Smith', email: 'jane@example.com', mobilePhone: '4125550101')

      expect { sync.run }.not_to change(User, :count)
      expect(state_of(by_email)).to include('contact_id' => '1')
    end

    it 'matches by number on the last ten digits and fills only blank fields', :aggregate_failures do
      user = create(:customer, firstname: 'Johnny', lastname: 'Doe', email: '', mobile: '412.555.0102', phone: '')
      book << contact(1, firstName: 'John', lastName: 'Doe-Smith', email: 'john@example.com', mobilePhone: '+1 412 555 0102', businessPhone: '4125550199')

      expect { sync.run }.not_to change(User, :count)
      expect(user.reload).to have_attributes(firstname: 'Johnny', lastname: 'Doe', email: 'john@example.com', phone: '+14125550199')
    end

    it 'never overwrites a name or email set on the user' do
      user = create(:customer, firstname: 'Directory', lastname: 'Name', email: 'dir@example.com', mobile: '+14125550103')
      book << contact(1, firstName: 'Phone', lastName: 'Book', email: 'other@example.com', mobilePhone: '4125550103')

      sync.run
      expect(user.reload).to have_attributes(firstname: 'Directory', lastname: 'Name', email: 'dir@example.com')
    end

    it 'renames a placeholder customer named after its number', :aggregate_failures do
      placeholder = create(:customer, firstname: '+14125550104', lastname: '', email: '', phone: '+14125550104')
      book << contact(1, firstName: 'Paula', lastName: 'Placeholder', mobilePhone: '4125550104')

      expect { sync.run }.not_to change(User, :count)
      expect(placeholder.reload).to have_attributes(firstname: 'Paula', lastname: 'Placeholder')
    end

    it 'prefers a named user over a placeholder on the same number' do
      named = create(:customer, firstname: 'Real', lastname: 'Person', mobile: '+14125550105')
      create(:customer, firstname: '+14125550105', lastname: '', email: '', phone: '+14125550105')
      book << contact(1, firstName: 'Real', lastName: 'Person', mobilePhone: '4125550105')

      sync.run
      expect(state_of(named)).to include('contact_id' => '1')
    end

    it 'skips a contact whose numbers belong to different named users' do
      create(:customer, firstname: 'A', lastname: 'One', mobile: '+14125550106')
      create(:customer, firstname: 'B', lastname: 'Two', mobile: '+14125550107')
      book << contact(1, firstName: 'Shared', lastName: 'Line', mobilePhone: '4125550106', businessPhone: '4125550107')

      result = sync.run
      expect(result[:import]).to include(skipped: 1, created: 0)
    end

    it 'skips contacts without a name or without any number and email' do
      book << contact(1, firstName: '', lastName: '', mobilePhone: '4125550108')
      book << contact(2, firstName: 'No', lastName: 'Numbers')

      expect { sync.run }.not_to change(User, :count)
    end

    it 'updates the same user on the next run instead of creating a duplicate' do
      book << contact(1, firstName: 'Jane', lastName: 'Smith', mobilePhone: '4125550109')
      sync.run
      book.first['mobilePhone'] = '4125550110'

      expect { described_class.new(channel.reload).tap { |s| allow(s).to receive(:pause) }.run }.not_to change(User, :count)
    end

    it 'skips contacts the export created (loop prevention)' do
      book << contact(1, firstName: 'Dir', lastName: 'User', mobilePhone: '4125550111', notes: described_class::EXPORT_NOTE)
      expect { sync.run }.not_to change(User, :count)
    end
  end

  describe 'export' do
    let(:import) { false }
    let(:org)    { create(:organization, name: 'Tenant Org') }

    it 'creates a contact for a directory user with a number', :aggregate_failures do
      user = directory_user(firstname: 'Dana', lastname: 'Dir', email: 'dana@example.com', mobile: '+14125550201', phone: '+14125550202', organization: org)

      result = sync.run
      expect(result[:export]).to include(created: 1)
      expect(client.created.first).to include(
        'firstName' => 'Dana', 'lastName' => 'Dir', 'company' => 'Tenant Org', 'email' => 'dana@example.com',
        'mobilePhone' => '+14125550201', 'businessPhone' => '+14125550202',
      )
      expect(client.created.first['notes']).to include(described_class::EXPORT_MARKER)
      expect(state_of(user)).to include('origin' => 'export', 'contact_id' => client.created.first['id'].to_s)
    end

    it 'ignores users without a directory authorization or without numbers, and inactive users' do
      create(:customer, firstname: 'Not', lastname: 'Directory', mobile: '+14125550203')
      directory_user(firstname: 'No', lastname: 'Number', mobile: '', phone: '')
      directory_user(firstname: 'Gone', lastname: 'User', mobile: '+14125550204', active: false)

      sync.run
      expect(client.created).to be_empty
    end

    it 'does not touch or duplicate a contact staff created for the same number', :aggregate_failures do
      book << contact(50, firstName: 'Staff', lastName: 'Made', mobilePhone: '(412) 555-0205')
      user = directory_user(firstname: 'Dana', lastname: 'Dir', mobile: '+14125550205')

      result = sync.run
      expect(client.created).to be_empty
      expect(client.updated).to be_empty
      expect(result[:export]).to include(skipped: 1)
      expect(state_of(user)).to include('origin' => 'manual', 'contact_id' => '50')
    end

    it 'updates its own contact when the user changes and keeps fields staff added', :aggregate_failures do
      user = directory_user(firstname: 'Dana', lastname: 'Dir', mobile: '+14125550206')
      sync.run
      book.first['homePhone'] = '+14125559999'
      user.update!(lastname: 'Married', organization: org)

      result = described_class.new(channel.reload).tap { |s| allow(s).to receive(:pause) }.run
      expect(result[:export]).to include(updated: 1, created: 0)
      expect(book.first).to include('lastName' => 'Married', 'company' => 'Tenant Org', 'homePhone' => '+14125559999')
      expect(book.first['notes']).to include(described_class::EXPORT_MARKER)
    end

    it 'writes nothing when nothing changed' do
      directory_user(firstname: 'Dana', lastname: 'Dir', mobile: '+14125550207')
      sync.run

      result = described_class.new(channel.reload).tap { |s| allow(s).to receive(:pause) }.run
      expect(result[:export]).to include(unchanged: 1, created: 0, updated: 0)
    end

    it 'leaves its contact alone once staff remove the marker', :aggregate_failures do
      user = directory_user(firstname: 'Dana', lastname: 'Dir', mobile: '+14125550208')
      sync.run
      book.first['notes'] = 'Our plumber'
      user.update!(lastname: 'Changed')

      described_class.new(channel.reload).tap { |s| allow(s).to receive(:pause) }.run
      expect(client.updated).to be_empty
      expect(state_of(user)).to include('origin' => 'manual')
    end

    it 'does not recreate a contact staff deleted', :aggregate_failures do
      user = directory_user(firstname: 'Dana', lastname: 'Dir', mobile: '+14125550209')
      sync.run
      book.clear

      described_class.new(channel.reload).tap { |s| allow(s).to receive(:pause) }.run
      expect(client.created.size).to eq(1)
      expect(state_of(user)).to include('origin' => 'deleted')
    end

    it 'creates one contact for a number two directory users share' do
      directory_user(firstname: 'First', lastname: 'User', mobile: '+14125550210')
      directory_user(firstname: 'Second', lastname: 'User', mobile: '+14125550210')

      sync.run
      expect(client.created.size).to eq(1)
    end

    it 'is not imported back when import is on as well' do
      channel.options[:contact_import] = true
      channel.save!
      directory_user(firstname: 'Dana', lastname: 'Dir', mobile: '+14125550211')
      sync.run

      expect { described_class.new(channel.reload).tap { |s| allow(s).to receive(:pause) }.run }.not_to change(User, :count)
    end

    it 'spaces writes for the rate limit' do
      directory_user(firstname: 'One', lastname: 'User', mobile: '+14125550212')
      directory_user(firstname: 'Two', lastname: 'User', mobile: '+14125550213')

      sync.run
      expect(sync).to have_received(:pause).once
    end

    context 'when RingCentral refuses the write (403)' do
      before do
        client.failures << Kc::RingcentralApi::PermissionError.new('RingCentral API error (403): InsufficientPermissions')
        directory_user(firstname: 'One', lastname: 'User', mobile: '+14125550214')
        directory_user(firstname: 'Two', lastname: 'User', mobile: '+14125550215')
      end

      it 'stops the export and shows a clear message on the channel', :aggregate_failures do
        result = sync.run
        expect(client.created).to be_empty
        expect(result[:status]).to eq('completed_with_errors')
        expect(channel.reload.options[:last_contact_sync]['last_error']).to include('Contacts permission')
      end
    end

    context 'when RingCentral answers 429' do
      before do
        directory_user(firstname: 'One', lastname: 'User', mobile: '+14125550216')
      end

      it 'waits for Retry-After and tries again once', :aggregate_failures do
        client.failures << Kc::RingcentralApi::RateLimitError.new('RingCentral API error (429): rate', retry_after: 30)

        result = sync.run
        expect(sync).to have_received(:pause).with(30)
        expect(result[:export]).to include(created: 1)
      end

      it 'stops and leaves the rest for the next run when the limit persists', :aggregate_failures do
        2.times { client.failures << Kc::RingcentralApi::RateLimitError.new('RingCentral API error (429): rate', retry_after: 20) }
        directory_user(firstname: 'Two', lastname: 'User', mobile: '+14125550217')

        result = sync.run
        expect(result[:export]).to include(created: 0)
        expect(result[:last_error]).to include('next run')

        rerun = described_class.new(channel.reload).tap { |s| allow(s).to receive(:pause) }.run
        expect(rerun[:export]).to include(created: 2)
      end

      it 'stops at once when Retry-After is longer than a minute' do
        client.failures << Kc::RingcentralApi::RateLimitError.new('RingCentral API error (429): rate', retry_after: 600)

        sync.run
        expect(sync).not_to have_received(:pause).with(600)
      end
    end
  end

  it 'records a disabled run when neither direction is on' do
    channel.options[:contact_import] = false
    channel.options[:contact_export] = false
    channel.save!
    expect(described_class.new(channel).run[:status]).to eq('disabled')
  end
end
