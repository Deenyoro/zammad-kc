# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Ticket::Search do
  describe 'Duplicate results in search #3876' do
    let(:search)   { SecureRandom.uuid }
    let(:ticket)   { create(:ticket, group: Group.first) }
    let(:articles) { create_list(:ticket_article, 3, ticket: ticket, body: search) }
    let(:agent)    { create(:agent, groups: Group.all) }

    before do
      articles
    end

    it 'does not show up the same ticket twice if no elastic search is configured' do
      expect(Ticket.search(current_user: agent, query: search)).to eq([ticket])
    end
  end

  describe 'Missing wildcard search on fulltext search #5558', searchindex: true do
    let(:search)   { SecureRandom.uuid }
    let(:ticket)   { create(:ticket, group: Group.first) }
    let(:agent)    { create(:agent, groups: Group.all) }

    before do
      ticket
      searchindex_model_reload([Ticket])
    end

    it 'does not show up the same ticket twice if no elastic search is configured' do
      expect(Ticket.search(current_user: agent, query: '(state.name:new OR state.name:open) AND NOT customer.organization_id:* AND owner_id:1')).to eq([ticket])
    end
  end

  describe 'Add support for optional Elasticsearch asciifolding analyzer #5537', searchindex: true do
    let(:search)       { 'Ružovučký' }
    let(:search_fuzzy) { 'ruzovucky' }
    let!(:ticket)      { create(:ticket, title: 'Ružovučký koníček a sôvä spia', group: Group.first) }
    let(:agent)        { create(:agent, groups: Group.all) }

    before do
      searchindex_model_reload([Ticket])
    end

    it 'does find the ticket via asciifolding', :aggregate_failures do
      expect(Ticket.search(current_user: agent, query: search)).to eq([ticket])
      expect(Ticket.search(current_user: agent, query: search_fuzzy)).to eq([ticket])
    end

    context 'when disabled' do
      before do
        Setting.set('es_asciifolding', false)
        SearchIndexBackend.drop_index([Ticket])
        SearchIndexBackend.create_index([Ticket])
        searchindex_model_reload([Ticket])
      end

      it 'does not find the ticket without asciifolding', :aggregate_failures do
        expect(Ticket.search(current_user: agent, query: search)).to eq([ticket])
        expect(Ticket.search(current_user: agent, query: search_fuzzy)).to eq([])
      end
    end
  end

  describe 'Language detection mechanism #5476', searchindex: true do
    let(:ticket)  { create(:ticket, group: Group.first) }
    let(:article) { create(:ticket_article, ticket: ticket, detected_language: 'de') }
    let(:agent)   { create(:agent, groups: Group.all) }

    before do
      article
      searchindex_model_reload([Ticket])
    end

    shared_examples 'finding the ticket by its article attribute' do
      it 'finds the ticket by its article attribute' do
        expect(Ticket.search(current_user: agent, query: search)).to eq([ticket])
      end
    end

    context 'with language code' do
      let(:search) { 'article.detected_language:de' }

      it_behaves_like 'finding the ticket by its article attribute'
    end

    context 'with language name' do
      let(:search) { 'article.detected_language_name:german' }

      it_behaves_like 'finding the ticket by its article attribute'
    end
  end
end
