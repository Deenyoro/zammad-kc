# KC: run in a Zammad test environment after copying kc/ into the app tree
# (kc/script/apply-overlay.sh, then cp -r kc/spec/. spec/):
#   bundle exec rspec spec/lib/kc/ringcentral_api_spec.rb

require 'rails_helper'

RSpec.describe Kc::RingcentralApi do
  let(:api)      { described_class.new(client_id: 'id', client_secret: 'secret', access_token: 'token') }
  let(:base)     { 'https://platform.ringcentral.com/restapi/v1.0/account/~/extension/~/address-book/contact' }
  let(:contact)  { { 'firstName' => 'Jane', 'lastName' => 'Smith', 'mobilePhone' => '+14125550100' } }

  describe '#create_address_book_contact' do
    it 'posts the contact and returns the created record' do
      stub_request(:post, base)
        .with(body: contact.to_json, headers: { 'Authorization' => 'Bearer token' })
        .to_return(status: 200, body: contact.merge('id' => 77).to_json, headers: { 'Content-Type' => 'application/json' })

      expect(api.create_address_book_contact(contact)).to include('id' => 77)
    end

    it 'raises PermissionError on 403' do
      stub_request(:post, base).to_return(
        status: 403, body: { errorCode: 'InsufficientPermissions', message: 'In order to call this API endpoint, application needs to have [Contacts] permission' }.to_json,
      )

      expect { api.create_address_book_contact(contact) }.to raise_error(described_class::PermissionError, %r{Contacts})
    end

    it 'raises RateLimitError with Retry-After on 429', :aggregate_failures do
      stub_request(:post, base).to_return(status: 429, body: { errorCode: 'CMN-301', message: 'Request rate exceeded' }.to_json, headers: { 'Retry-After' => '42' })

      expect { api.create_address_book_contact(contact) }.to raise_error(described_class::RateLimitError) { |error|
        expect(error.retry_after).to eq(42)
      }
    end
  end

  describe '#update_address_book_contact' do
    it 'puts the contact to its id' do
      stub_request(:put, "#{base}/77").with(body: contact.to_json).to_return(status: 200, body: contact.merge('id' => 77).to_json)

      expect(api.update_address_book_contact(77, contact)).to include('id' => 77)
    end

    it 'refuses an id that is not a number' do
      expect { api.update_address_book_contact('../x', contact) }.to raise_error(ArgumentError)
    end
  end
end
