# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Service::AI::Agent::Run do
  let(:ai_agent) { create(:ai_agent, definition: agent_definition, action_definition: action_definition) }
  let(:ticket)   { create(:ticket) }
  let(:agent_definition) do
    {
      'role_description'    => 'Test AI Agent',
      'instruction'         => 'Analyze the ticket and provide recommendations',
      'instruction_context' => instruction_context,
      'result_structure'    => result_structure
    }
  end
  let(:instruction_context) do
    {
      'object_attributes' => {}
    }
  end
  let(:result_structure) do
    {
      'state_id'    => 'integer',
      'priority_id' => 'integer',
    }
  end
  let(:action_definition) do
    {
      'mapping' => {
        'ticket.priority_id' => {
          'value' => '#{ai_agent_result.priority_id}' # rubocop:disable Lint/InterpolationCheck
        },
        'ticket.state_id'    => {
          'value' => '#{ai_agent_result.state_id}' # rubocop:disable Lint/InterpolationCheck
        }
      }
    }
  end
  let(:ai_provider) { 'open_ai' }

  before do
    Setting.set('ai_provider', ai_provider)
  end

  describe '#execute' do
    subject(:service) { described_class.new(ai_agent: ai_agent, ticket: ticket) }

    context 'when AI service returns a successful result' do
      let(:ai_result_content) do
        {
          'state_id'    => Ticket::State.lookup(name: 'open').id,
          'priority_id' => Ticket::Priority.lookup(name: '3 high').id,
        }
      end
      let(:ai_result) do
        AI::Service::Result.new(
          content:       ai_result_content,
          stored_result: nil,
          fresh:         true
        )
      end

      before do
        allow_any_instance_of(AI::Service::AIAgent).to receive(:execute).and_return(ai_result)
      end

      it 'executes the AI agent service and applies changes to the ticket based on AI result' do
        expect { service.execute }
          .to change { ticket.reload.priority.name }.to('3 high')
          .and change { ticket.reload.state.name }.to('open')
      end

      context 'when no result structure is present' do
        let(:result_structure) { nil }
        let(:action_definition) do
          {
            'mapping' => {
              'ticket.priority_id' => {
                'value' => '#{ai_agent_result.content}' # rubocop:disable Lint/InterpolationCheck
              },
            }
          }
        end
        let(:ai_result_content) { Ticket::Priority.lookup(name: '3 high').id }

        it 'executes the AI agent service and applies changes to the ticket based on AI result' do
          expect { service.execute }.to change { ticket.reload.priority.name }.to('3 high')
        end
      end

      context 'when conditions are present in action_definition' do
        let(:result_structure) do
          {
            'state_id'         => 'integer',
            'priority_id'      => 'integer',
            'is_real_question' => 'boolean'
          }
        end
        let(:action_definition) do
          {
            'mapping'    => {
              'ticket.priority_id' => {
                'value' => '#{ai_agent_result.priority_id}' # rubocop:disable Lint/InterpolationCheck
              }
            },
            'conditions' => [
              {
                'condition' => {
                  'is_real_question' => false
                },
                'mapping'   => {
                  'ticket.state_id' => {
                    'value' => '#{ai_agent_result.state_id}' # rubocop:disable Lint/InterpolationCheck
                  }
                }
              }
            ]
          }
        end
        let(:ai_result_content) do
          {
            'priority_id'      => Ticket::Priority.lookup(name: '3 high').id,
            'state_id'         => Ticket::State.lookup(name: 'closed').id,
            'is_real_question' => false
          }
        end

        it 'applies base mapping and condition mapping when condition matches' do
          expect { service.execute }
            .to change { ticket.reload.priority.name }.to('3 high')
            .and change { ticket.reload.state.name }.to('closed')
        end

        context 'when condition does not match' do
          let(:ai_result_content) do
            {
              'priority_id'      => Ticket::Priority.lookup(name: '3 high').id,
              'state_id'         => Ticket::State.lookup(name: 'closed').id,
              'is_real_question' => true
            }
          end

          it 'applies only base mapping when condition does not match' do
            expect { service.execute }
              .to change { ticket.reload.priority.name }.to('3 high')
              .and not_change { ticket.reload.state.name }
          end
        end
      end
    end

    context 'when AI service raises an exception' do
      before do
        allow_any_instance_of(AI::Service::AIAgent).to receive(:execute).and_raise(AI::Provider::OutputFormatError, 'AI service error')
      end

      it 'raises the exception' do
        expect { service.execute }.to raise_error(Service::AI::Agent::Run::PermanentError, 'AI service error')
      end

      context 'when AI service raises an response error' do
        before do
          allow_any_instance_of(AI::Service::AIAgent).to receive(:execute).and_raise(AI::Provider::ResponseError, 'AI service error')
        end

        it 'raises the exception' do
          expect { service.execute }.to raise_error(Service::AI::Agent::Run::TemporaryError, 'AI service error')
        end
      end

      context 'when AI provider is not configured' do
        let(:ai_provider) { nil }

        it 'raises the exception' do
          expect { service.execute }.to raise_error(Service::CheckFeatureEnabled::FeatureDisabledError, 'AI provider is not configured.')
        end
      end
    end
  end
end
