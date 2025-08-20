# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Gql::Mutations::AIAssistance::TextTools::Run, :aggregate_failures, type: :graphql do
  context 'when accessing as an agent', authenticated_as: :agent do
    let(:agent)     { create(:agent) }
    let(:input)     { Faker::Lorem.unique.sentence }
    let(:output)    { Struct.new(:content, :stored_result, :fresh, keyword_init: true).new(content: Faker::Lorem.unique.paragraph, stored_result: nil, fresh: false) }
    let(:text_tool) { create(:ai_text_tool) }

    let(:query) do
      <<~MUTATION
        mutation aiAssistanceTextToolsRun($input: String!, $textToolId: ID!, $templateRenderContext: TemplateRenderContextInput!) {
          aiAssistanceTextToolsRun(input: $input, textToolId: $textToolId, templateRenderContext: $templateRenderContext) {
            output
          }
        }
      MUTATION
    end

    let(:variables) do
      {
        input:,
        textToolId:            gql.id(text_tool),
        templateRenderContext: {},
      }
    end

    before do
      Setting.set('ai_assistance_text_tools', true)
      Setting.set('ai_provider', 'zammad_ai')

      allow_any_instance_of(AI::Service::TextTool)
        .to receive(:execute)
        .and_return(output)

      gql.execute(query, variables: variables)
    end

    it 'returns improved text' do
      expect(gql.result.data['output']).to eq(output[:content])
    end

    it_behaves_like 'graphql responds with error if unauthenticated'
  end
end
