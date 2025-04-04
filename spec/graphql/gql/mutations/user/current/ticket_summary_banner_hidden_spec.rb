# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Gql::Mutations::User::Current::TicketSummaryBannerHidden, type: :graphql do
  let(:user) { create(:agent) }

  let(:mutation) do
    <<~GQL
      mutation userCurrentTicketSummaryBannerHidden($hidden: Boolean!) {
        userCurrentTicketSummaryBannerHidden(hidden: $hidden) {
          success
          errors {
            message
            field
          }
        }
      }
    GQL
  end

  let(:variables) { { hidden: true } }

  def execute_graphql_query
    gql.execute(mutation, variables: variables)
  end

  context 'when user is not authenticated' do
    before do
      gql.execute(mutation, variables: variables)
    end

    it 'returns an error' do
      expect(execute_graphql_query.error_message).to eq('Authentication required')
    end
  end

  context 'when user is authenticated', authenticated_as: :user do
    context 'with ticket summary banner is set to hidden' do
      it 'updates user profile ticket summary banner hidden setting' do
        expect { execute_graphql_query }.to change { user.reload.preferences['ticket_summary_banner_hidden'] }.from(nil).to(true)
      end
    end
  end
end
