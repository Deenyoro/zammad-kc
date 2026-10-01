# KC: run in a Zammad test environment after copying kc/ into the app tree
# (kc/script/apply-overlay.sh, then cp -r kc/spec/. spec/):
#   bundle exec rspec spec/services/kc/phone_contacts_spec.rb

require 'rails_helper'

RSpec.describe Kc::PhoneContacts do
  let(:ringcentral_book) { {} }
  let(:freepbx_book)     { {} }

  before do
    allow(described_class).to receive_messages(ringcentral_book: ringcentral_book, freepbx_book: freepbx_book)
  end

  describe '.match_key' do
    it 'compares North American numbers on their last ten digits', :aggregate_failures do
      expect(described_class.match_key('+1 (412) 555-0100')).to eq('4125550100')
      expect(described_class.match_key('4125550100')).to eq('4125550100')
    end

    it 'ignores short codes and extensions' do
      expect(described_class.match_key('201')).to be_nil
    end
  end

  describe '.placeholder?' do
    it 'is true for a customer named after a number' do
      expect(described_class.placeholder?(build(:customer, firstname: '+14125550100', lastname: '', email: ''))).to be(true)
    end

    it 'is false for a named customer' do
      expect(described_class.placeholder?(build(:customer, firstname: 'Jane', lastname: 'Smith'))).to be(false)
    end
  end

  describe '.name_for' do
    context 'with a Zammad user whose number is stored in another format' do
      before { create(:customer, firstname: 'Jane', lastname: 'Smith', mobile: '(412) 555-0100') }

      it 'returns the user name' do
        expect(described_class.name_for('+14125550100')).to eq('Jane Smith')
      end
    end

    context 'with only a placeholder user and a RingCentral contact' do
      let(:ringcentral_book) { { '4125550100' => 'Jane Smith' } }

      before { create(:customer, firstname: '+14125550100', lastname: '', email: '', phone: '+14125550100') }

      it 'returns the RingCentral contact' do
        expect(described_class.name_for('+14125550100')).to eq('Jane Smith')
      end
    end

    context 'with only a FreePBX phonebook entry' do
      let(:freepbx_book) { { '4125550100' => 'PBX Person' } }

      it 'returns the phonebook name' do
        expect(described_class.name_for('+14125550100')).to eq('PBX Person')
      end
    end

    it 'returns nil for an unknown number' do
      expect(described_class.name_for('+14125550199')).to be_nil
    end
  end

  describe '.display' do
    let(:ringcentral_book) { { '4125550100' => 'Jane Smith' } }

    it 'puts the name in front of the number' do
      expect(described_class.display('4125550100')).to eq('Jane Smith (+14125550100)')
    end

    it 'keeps the bare number when nobody matches' do
      expect(described_class.display('+14125550199')).to eq('+14125550199')
    end
  end

  describe '.find_or_create_customer' do
    let(:ringcentral_book) { { '4125550100' => 'Jane Smith' } }

    it 'names a new customer after the contact' do
      user = described_class.find_or_create_customer('+14125550100')
      expect(user).to have_attributes(firstname: 'Jane', lastname: 'Smith', phone: '+14125550100')
    end

    it 'renames an existing placeholder customer', :aggregate_failures do
      placeholder = create(:customer, firstname: '+14125550100', lastname: '', email: '', phone: '+14125550100')
      expect(described_class.find_or_create_customer('+14125550100')).to eq(placeholder)
      expect(placeholder.reload).to have_attributes(firstname: 'Jane', lastname: 'Smith')
    end

    it 'leaves a named customer alone' do
      named = create(:customer, firstname: 'Janet', lastname: 'Doe', phone: '+14125550100')
      described_class.find_or_create_customer('+14125550100')
      expect(named.reload).to have_attributes(firstname: 'Janet', lastname: 'Doe')
    end
  end
end
