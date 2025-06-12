# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'
require 'elasticsearch'

RSpec.describe 'AI::VectorDB Version Check' do # rubocop:disable RSpec/DescribeClass
  subject(:instance) { AI::VectorDB.new }

  context 'when Elasticsearch version is within the supported range' do
    before do
      indices_client = instance_double(Elasticsearch::API::Indices::IndicesClient, exists?: true)
      client = instance_double(Elasticsearch::Client, indices: indices_client, info: { 'version' => { 'number' => '8.12.0' } })
      allow(instance).to receive_messages(client: client)
    end

    it 'does not raise an error' do
      expect { instance.ping! }.not_to raise_error
    end
  end

  context 'when Elasticsearch version is below the minimum required version' do
    before do
      indices_client = instance_double(Elasticsearch::API::Indices::IndicesClient, exists?: true)
      client = instance_double(Elasticsearch::Client, indices: indices_client, info: { 'version' => { 'number' => '8.10.0' } })
      allow(instance).to receive_messages(client: client)
    end

    it 'raises an error' do
      expect { instance.ping! }.to raise_error(AI::VectorDB::Error, 'Incompatible Elasticsearch version')
    end

    context 'when Elasticsearch version is above the maximum required version' do
      before do
        indices_client = instance_double(Elasticsearch::API::Indices::IndicesClient, exists?: true)
        client = instance_double(Elasticsearch::Client, indices: indices_client, info: { 'version' => { 'number' => '8.19.0' } })
        allow(instance).to receive_messages(client: client)
      end

      it 'raises an error' do
        expect { instance.ping! }.to raise_error(AI::VectorDB::Error, 'Incompatible Elasticsearch version')
      end
    end
  end
end
