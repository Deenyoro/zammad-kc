import * as Types from '#shared/graphql/types.ts';

import * as Mocks from '#tests/graphql/builders/mocks.ts'
import * as Operations from './userCurrentTicketSummaryBannerHidden.api.ts'
import * as ErrorTypes from '#shared/types/error.ts'

export function mockUserCurrentTicketSummaryBannerHiddenMutation(defaults: Mocks.MockDefaultsValue<Types.UserCurrentTicketSummaryBannerHiddenMutation, Types.UserCurrentTicketSummaryBannerHiddenMutationVariables>) {
  return Mocks.mockGraphQLResult(Operations.UserCurrentTicketSummaryBannerHiddenDocument, defaults)
}

export function waitForUserCurrentTicketSummaryBannerHiddenMutationCalls() {
  return Mocks.waitForGraphQLMockCalls<Types.UserCurrentTicketSummaryBannerHiddenMutation>(Operations.UserCurrentTicketSummaryBannerHiddenDocument)
}

export function mockUserCurrentTicketSummaryBannerHiddenMutationError(message: string, extensions: {type: ErrorTypes.GraphQLErrorTypes }) {
  return Mocks.mockGraphQLResultWithError(Operations.UserCurrentTicketSummaryBannerHiddenDocument, message, extensions);
}
