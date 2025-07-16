# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'AI::Agent', :aggregate_failures, authenticated_as: :user, type: :request do
  let(:user) { create(:admin) }

  describe '#index' do
    it 'returns a list of AI agents' do
      create(:ai_agent, name: 'Test AI Agent 1')
      create(:ai_agent, name: 'Test AI Agent 2')

      get '/api/v1/ai_agents', as: :json

      expect(response).to have_http_status(:ok)

      expect(json_response).to be_a(Array)
      expect(json_response.size).to eq(2)
      expect(json_response.map { |agent| agent['name'] }).to include('Test AI Agent 1', 'Test AI Agent 2')
    end
  end

  describe '#show' do
    it 'returns a specific AI agent' do
      ai_agent = create(:ai_agent, name: 'Test AI Agent')

      get "/api/v1/ai_agents/#{ai_agent.id}", as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response).to be_a(Hash)
      expect(json_response['name']).to eq('Test AI Agent')
    end

    context 'when full assets are requested' do
      it 'returns the AI agent with assets' do
        ai_agent = create(:ai_agent, name: 'Test AI Agent with Assets')

        trigger = create(:trigger, perform: { 'ai.ai_agent' => { 'ai_agent_id' => ai_agent.id } })
        job = create(:job, perform: { 'ai.ai_agent' => { 'ai_agent_id' => ai_agent.id } })

        get "/api/v1/ai_agents/#{ai_agent.id}?full=true", as: :json

        expect(response).to have_http_status(:ok)
        expect(json_response).to be_a(Hash)

        expect(json_response['id']).to eq(ai_agent.id)
        expect(json_response['assets']).to be_present
        expect(json_response['assets']).to be_a(Hash)
        expect(json_response['assets']['AIAgent']).to be_a(Hash)
        expect(json_response['assets']['AIAgent'][ai_agent.id.to_s]).to be_a(Hash)
        expect(json_response['assets']['AIAgent'][ai_agent.id.to_s]['id']).to eq(ai_agent.id)
        expect(json_response['assets']['AIAgent'][ai_agent.id.to_s]['name']).to eq('Test AI Agent with Assets')

        expect(json_response['assets']['AIAgent'][ai_agent.id.to_s]['references']).to be_a(Hash)
        expect(json_response['assets']['AIAgent'][ai_agent.id.to_s]['references']).to be_a(Hash)
        expect(json_response['assets']['AIAgent'][ai_agent.id.to_s]['references']['Job']).to be_a(Array)
        expect(json_response['assets']['AIAgent'][ai_agent.id.to_s]['references']['Job'].size).to eq(1)
        expect(json_response['assets']['AIAgent'][ai_agent.id.to_s]['references']['Job'].first['id']).to eq(job.id)
        expect(json_response['assets']['AIAgent'][ai_agent.id.to_s]['references']['Job'].first['name']).to eq(job.name)
        expect(json_response['assets']['AIAgent'][ai_agent.id.to_s]['references']['Trigger']).to be_a(Array)
        expect(json_response['assets']['AIAgent'][ai_agent.id.to_s]['references']['Trigger'].size).to eq(1)
        expect(json_response['assets']['AIAgent'][ai_agent.id.to_s]['references']['Trigger'].first['id']).to eq(trigger.id)
        expect(json_response['assets']['AIAgent'][ai_agent.id.to_s]['references']['Trigger'].first['name']).to eq(trigger.name)
      end
    end
  end

  describe '#create' do
    it 'creates a new AI agent' do
      post '/api/v1/ai_agents', params: { name: 'New AI Agent' }, as: :json

      expect(response).to have_http_status(:created)
      expect(json_response).to be_a(Hash)
      expect(json_response['name']).to eq('New AI Agent')
    end
  end

  describe '#update' do
    it 'updates an existing AI agent' do
      ai_agent = create(:ai_agent, name: 'Old AI Agent')

      put "/api/v1/ai_agents/#{ai_agent.id}", params: { name: 'Updated AI Agent' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response).to be_a(Hash)
      expect(json_response['name']).to eq('Updated AI Agent')
    end
  end

  describe '#search' do
    it 'searches for AI agents' do
      create(:ai_agent, name: 'Searchable AI Agent 1')
      create(:ai_agent, name: 'Searchable AI Agent 2')

      get '/api/v1/ai_agents/search', params: { query: 'Searchable' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response).to be_a(Array)
      expect(json_response.size).to eq(2)
      expect(json_response.map { |agent| agent['name'] }).to include('Searchable AI Agent 1', 'Searchable AI Agent 2')
    end
  end

  describe '#destroy' do
    it 'deletes an AI agent' do
      ai_agent = create(:ai_agent, name: 'AI Agent to Delete')

      delete "/api/v1/ai_agents/#{ai_agent.id}", as: :json

      expect(response).to have_http_status(:ok)
      expect { AI::Agent.find(ai_agent.id) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'returns an error if the AI agent has references' do
      ai_agent = create(:ai_agent, name: 'AI Agent with References')

      trigger = create(:trigger, perform: { 'ai.ai_agent' => { 'ai_agent_id' => ai_agent.id } })

      delete "/api/v1/ai_agents/#{ai_agent.id}", as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_response['error']).to eq('This %s is referenced by another object and thus cannot be deleted: %s')
      expect(json_response['unprocessable_entity']).to include('AI Agent').and include("Trigger / #{trigger.name} (##{trigger.id})")
    end
  end
end
