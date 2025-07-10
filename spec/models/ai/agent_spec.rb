# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'
require 'models/application_model_examples'
require 'models/concerns/has_xss_sanitized_note_examples'

RSpec.describe AI::Agent, current_user_id: 1, type: :model do
  subject(:ai_agent) { create(:ai_agent, action_definition:) }

  let(:action_definition) { {} }

  it_behaves_like 'ApplicationModel'
  it_behaves_like 'HasXssSanitizedNote', model_factory: :trigger

  describe 'Validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).case_insensitive }
    it { is_expected.to validate_length_of(:note).is_at_most(250) }
  end

  describe '#destroy' do
    context 'when no dependencies' do
      it 'removes the object' do
        expect { ai_agent.destroy }.to change(ai_agent, :destroyed?).to true
      end
    end

    context 'when related object exists' do
      let!(:trigger) { create(:trigger, perform: { 'ai.ai_agent' => { 'ai_agent_id' => ai_agent.id.to_s } }) }

      it 'raises error with details' do
        expect { ai_agent.destroy }
          .to raise_exception(
            be_an_instance_of(Exceptions::UnprocessableEntity)
            .and(have_attributes(
                   message: 'This %s is referenced by another object and thus cannot be deleted: %s',
                   entity:  eq(['AI Agent', "Trigger / #{trigger.name} (##{trigger.id})"])
                 ))
          )
      end
    end
  end

  describe '.working_on' do
    let(:ticket)   { create(:ticket) }
    let(:article)  { create(:ticket_article, ticket:) }
    let(:trigger) do
      create(:trigger,
             perform: {
               'ai.ai_agent' => { 'ai_agent_id' => ai_agent.id }
             })
    end

    it 'returns empty scope when no agents active' do
      expect(described_class.working_on(ticket)).to be_empty
    end

    it 'lists agents working on a ticket' do
      TriggerAIAgentJob.perform_later(trigger, ticket, nil)

      expect(described_class.working_on(ticket)).to include(ai_agent)
    end
  end
end
