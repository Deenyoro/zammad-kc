# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Service::AI::Agent::Run::Context::Instruction, type: :service do
  let(:group) { create(:group, name: 'Example Group', note: 'An example group description.') }
  let(:object_attributes_context) do
    {
      'group_id'    => [group.id],
      'priority_id' => [], # this means all priorities
      'type'        => ['Incident']
    }
  end
  let(:instruction_context) do
    {
      'object_attributes' => object_attributes_context
    }
  end
  let(:instruction) { described_class.new(instruction_context: instruction_context) }

  let(:expected_result) do
    {
      object_attributes: {
        'group_id'    => { items: [{
          value: group.id,
          label: 'Example Group',
        }], label: 'Group' },
        'priority_id' => { items: Ticket::Priority.all.map do |priority|
          {
            value: priority.id,
            label: priority.name,
          }
        end, label: 'Priority' },
        'type'        => { items: [ { value: 'Incident', label: 'Incident' } ], label: 'Type' }
      }
    }
  end

  describe '#prepare' do
    context 'when object_attributes_context is blank' do
      let(:instruction_context) do
        {
          object_attributes: {}
        }
      end
      let(:expected_result) { {} }

      it 'returns empty hash' do
        expect(instruction.prepare).to eq(expected_result)
      end
    end

    context 'when object_attributes_context is present' do
      it 'returns prepared instruction context' do
        result = instruction.prepare

        expect(result[:object_attributes]).to eq(expected_result[:object_attributes])
      end
    end
  end
end
