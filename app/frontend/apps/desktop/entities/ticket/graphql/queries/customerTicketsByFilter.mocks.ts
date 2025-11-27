import * as Types from '#shared/graphql/types.ts';

import * as Mocks from '#tests/graphql/builders/mocks.ts'
import * as Operations from './customerTicketsByFilter.api.ts'
import * as ErrorTypes from '#shared/types/error.ts'

export function mockCustomerTicketsByFilterQuery(defaults: Mocks.MockDefaultsValue<Types.CustomerTicketsByFilterQuery, Types.CustomerTicketsByFilterQueryVariables>) {
  return Mocks.mockGraphQLResult(Operations.CustomerTicketsByFilterDocument, defaults)
}

export function waitForCustomerTicketsByFilterQueryCalls() {
  return Mocks.waitForGraphQLMockCalls<Types.CustomerTicketsByFilterQuery>(Operations.CustomerTicketsByFilterDocument)
}

export function mockCustomerTicketsByFilterQueryError(message: string, extensions: {type: ErrorTypes.GraphQLErrorTypes }) {
  return Mocks.mockGraphQLResultWithError(Operations.CustomerTicketsByFilterDocument, message, extensions);
}
