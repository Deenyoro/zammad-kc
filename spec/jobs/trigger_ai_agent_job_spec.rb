# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe TriggerAIAgentJob, type: :job do
  subject(:ai_agent) { create(:ai_agent) }

  let(:ticket)   { create(:ticket) }
  let(:article)  { create(:ticket_article, ticket:) }

  let(:perform) do
    described_class.perform_now(
      trigger,
      ticket,
      article,
      changes:        nil,
      user_id:        nil,
      execution_type: nil,
      event_type:     nil,
    )
  end

  let(:trigger) do
    create(:trigger,
           perform: {
             'ai.ai_agent' => { 'ai_agent_id' => ai_agent.id }
           })
  end

  let(:job) do
    described_class.perform_later(
      trigger,
      ticket,
      article,
      changes:        nil,
      user_id:        nil,
      execution_type: nil,
      event_type:     nil,
    )
  end

  context 'when serialized model argument gets deleted' do
    shared_examples 'handle deleted argument models' do
      it 'raises no error' do
        expect { ActiveJob::Base.execute job.serialize }.not_to raise_error
      end

      it "doesn't perform request" do
        expect_any_instance_of(Service::AI::Agent::Run).not_to receive(:execute)
        ActiveJob::Base.execute job.serialize
      end
    end

    context 'when Trigger gets deleted' do
      before { trigger.destroy! }

      include_examples 'handle deleted argument models'
    end

    context 'when Ticket gets deleted' do
      before { article.destroy! && ticket.destroy! }

      include_examples 'handle deleted argument models'
    end

    context 'when Article gets deleted' do
      before { article.destroy! }

      include_examples 'handle deleted argument models'
    end
  end

  describe '#perform' do
    let(:response_status) { 200 }
    let(:payload) do
      {
        ticket:  payload_ticket,
        article: payload_article,
      }
    end

    let(:headers) do
      {
        'Content-Type'     => 'application/json; charset=utf-8',
        'User-Agent'       => 'Zammad User Agent',
        'X-Zammad-Trigger' => trigger.name,
      }
    end

    let(:response_body) do
      {}.to_json
    end

    let(:response_headers) { {} }

    before do
      allow(Service::AI::Agent::Run).to receive(:new).and_call_original
      allow_any_instance_of(Service::AI::Agent::Run).to receive(:execute)
    end

    it 'executes the AI Agent service', aggregate_failures: true do
      expect_any_instance_of(Service::AI::Agent::Run).to receive(:execute)

      perform

      expect(Service::AI::Agent::Run).to have_received(:new).with(ai_agent:, ticket:, article:)
    end

    context 'when trigger was modified in meantime to not have AI agent anymore' do
      let(:trigger) { create(:trigger) }

      it 'throws no errors' do
        expect { perform }.not_to raise_error
      end

      it 'logs an error' do
        allow(Rails.logger).to receive(:error)

        perform

        expect(Rails.logger).to have_received(:error).with(%r{Can't find ai_agent_id for Trigger})
      end
    end
  end

  describe 'Redis agents-in-progress tracker' do
    context 'when adding AI Agent to the list' do
      it 'adds AI agent to the list when job is added' do
        described_class.perform_later(trigger, ticket, nil)

        expect(described_class.working_on(ticket)).to include(ai_agent.id.to_s)
      end

      it 'expires added Agents after inactivity' do
        stub_const('TriggerAIAgentJob::EXPIRE_ONGOING_AGENTS', 1)

        described_class.perform_later(trigger, ticket, nil)

        expect { sleep 2 }
          .to change { described_class.working_on(ticket) }
          .to []
      end
    end

    context 'when AI agent is already in the list' do
      before do
        described_class.redis.sadd(described_class.redis_key(ticket), ai_agent.id)
      end

      it 'removes AI agent from the list when job is done' do
        allow_any_instance_of(described_class).to receive(:perform)

        expect { perform }
          .to change { described_class.working_on(ticket) }
          .to []
      end

      it 'removes AI agent from the list when job throws an error' do
        allow_any_instance_of(described_class).to receive(:perform).and_raise(Service::AI::Agent::Run::PermanentError)

        expect { perform }
          .to change { described_class.working_on(ticket) }
          .to []
      end

      it 'does not remove AI agent from the list when job is retried' do
        allow_any_instance_of(described_class).to receive(:perform).and_raise(Service::AI::Agent::Run::TemporaryError)

        expect { perform }
          .not_to change { described_class.working_on(ticket) }
      end

      it 'removes AI agent from the list when job is retried enough times' do
        allow_any_instance_of(described_class).to receive(:perform).and_raise(Service::AI::Agent::Run::TemporaryError)

        4.times { ActiveJob::Base.execute job.serialize }

        expect {  ActiveJob::Base.execute job.serialize }
          .to change { described_class.working_on(ticket) }
          .to []
      end
    end
  end

  describe '.working_on' do
    let(:other_ticket)   { create(:ticket) }
    let(:other_article)  { create(:ticket_article, ticket: other_ticket) }
    let(:other_ai_agent) { create(:ai_agent) }

    let(:other_trigger) do
      create(:trigger,
             perform: {
               'ai.ai_agent' => { 'ai_agent_id' => other_ai_agent.id }
             })
    end

    let(:other_job) do
      described_class.perform_later(
        other_trigger,
        other_ticket,
        other_article,
        changes:        nil,
        user_id:        nil,
        execution_type: nil,
        event_type:     nil,
      )
    end

    it 'returns empty array when no agents are working on the ticket' do
      expect(described_class.working_on(ticket)).to be_empty
    end

    it 'returns array with agent ID when an agent is working on the ticket' do
      job

      expect(described_class.working_on(ticket)).to contain_exactly(ai_agent.id.to_s)
    end

    context 'when multiple agents are working on the same ticket' do
      let(:other_ticket) { ticket }
      let(:other_article) { article }

      it 'returns both agents' do
        job
        other_job

        expect(described_class.working_on(ticket)).to contain_exactly(ai_agent.id.to_s, other_ai_agent.id.to_s)
      end
    end

    context 'when multiple agents are working on different tickets' do
      it 'returns agent ID working on a given ticket if agents are working on different tickets' do
        job
        other_job

        expect(described_class.working_on(ticket)).to contain_exactly(ai_agent.id.to_s)
      end
    end
  end
end
