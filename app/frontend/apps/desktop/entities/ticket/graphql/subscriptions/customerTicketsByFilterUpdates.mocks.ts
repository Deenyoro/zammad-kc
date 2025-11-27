import * as Types from '#shared/graphql/types.ts';

import * as Mocks from '#tests/graphql/builders/mocks.ts'
import * as Operations from './customerTicketsByFilterUpdates.api.ts'
import * as ErrorTypes from '#shared/types/error.ts'

export function getCustomerTicketsByFilterUpdatesSubscriptionHandler() {
  return Mocks.getGraphQLSubscriptionHandler<Types.CustomerTicketsByFilterUpdatesSubscription>(Operations.CustomerTicketsByFilterUpdatesDocument)
}
