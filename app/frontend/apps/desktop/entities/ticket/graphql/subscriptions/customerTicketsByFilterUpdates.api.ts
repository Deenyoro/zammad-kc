import * as Types from '#shared/graphql/types.ts';

import gql from 'graphql-tag';
import * as VueApolloComposable from '@vue/apollo-composable';
import * as VueCompositionApi from 'vue';
export type ReactiveFunction<TParam> = () => TParam;

export const CustomerTicketsByFilterUpdatesDocument = gql`
    subscription customerTicketsByFilterUpdates($customerId: ID!) {
  ticketCustomerTicketsByFilterUpdates(customerId: $customerId) {
    listChanged
  }
}
    `;
export function useCustomerTicketsByFilterUpdatesSubscription(variables: Types.CustomerTicketsByFilterUpdatesSubscriptionVariables | VueCompositionApi.Ref<Types.CustomerTicketsByFilterUpdatesSubscriptionVariables> | ReactiveFunction<Types.CustomerTicketsByFilterUpdatesSubscriptionVariables>, options: VueApolloComposable.UseSubscriptionOptions<Types.CustomerTicketsByFilterUpdatesSubscription, Types.CustomerTicketsByFilterUpdatesSubscriptionVariables> | VueCompositionApi.Ref<VueApolloComposable.UseSubscriptionOptions<Types.CustomerTicketsByFilterUpdatesSubscription, Types.CustomerTicketsByFilterUpdatesSubscriptionVariables>> | ReactiveFunction<VueApolloComposable.UseSubscriptionOptions<Types.CustomerTicketsByFilterUpdatesSubscription, Types.CustomerTicketsByFilterUpdatesSubscriptionVariables>> = {}) {
  return VueApolloComposable.useSubscription<Types.CustomerTicketsByFilterUpdatesSubscription, Types.CustomerTicketsByFilterUpdatesSubscriptionVariables>(CustomerTicketsByFilterUpdatesDocument, variables, options);
}
export type CustomerTicketsByFilterUpdatesSubscriptionCompositionFunctionResult = VueApolloComposable.UseSubscriptionReturn<Types.CustomerTicketsByFilterUpdatesSubscription, Types.CustomerTicketsByFilterUpdatesSubscriptionVariables>;