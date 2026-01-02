# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Gql::Queries::User::History, timezone: 'Europe/Berlin', type: :graphql do
  context 'when fetching history of a user' do
    let(:user)   { create(:user) }
    let(:group)  { create(:group) }
    let(:owner)  { create(:user) }
    let(:ticket) { create(:ticket, group:, owner:, created_by: owner) }

    let(:variables) { { userId: gql.id(user) } }

    let(:query) do
      <<~QUERY
        query userHistory($userId: ID!) {
          userHistory(userId: $userId) {
            createdAt
            records {
              issuer {
                ... on User {
                  fullname
                }
                ... on Trigger {
                  id
                  internalId
                  name
                }
                ... on Job {
                  id
                  internalId
                  name
                }
                ... on PostmasterFilter {
                  id
                  internalId
                  name
                }
                ... on ObjectClass {
                  klass
                  info
                }
              }
              events {
                createdAt
                action
                object {
                  ... on Ticket {
                    title
                  }
                  ... on TicketArticle {
                    body
                  }
                  ... on ObjectClass {
                    klass
                    info
                  }
                }
                attribute
                changes
              }
            }
          }
        }
      QUERY
    end

    before do
      Time.use_zone('UTC') do
        freeze_time

        travel_to(2.days.ago) do
          ticket
          ticket.update!(title: 'New title', updated_by: create(:user))
        end

        travel_to(1.day.ago) do
          ticket.update!(title: 'Another title', updated_by: create(:user))
        end
      end
      gql.execute(query, variables:)
    end

    context 'with authenticated session', authenticated_as: :authenticated do
      context 'when user has no access to ticket' do
        let(:authenticated) { create(:customer) }

        it 'raises an error' do
          expect(gql.result.error_type).to eq(Exceptions::Forbidden)
        end
      end

      context 'with agent access' do
        let(:authenticated) { create(:agent, groups: [group]) }

        it 'returns grouped history records' do
          expect(gql.result.data).to be_present
        end
      end

      context 'with admin access' do
        let(:authenticated) { create(:admin, groups: [group]) }

        it 'returns grouped history records' do
          expect(gql.result.data).to be_present
        end
      end
    end
  end
end
