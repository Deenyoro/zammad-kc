import * as Types from '#shared/graphql/types.ts';

import gql from 'graphql-tag';
import * as VueApolloComposable from '@vue/apollo-composable';
import * as VueCompositionApi from 'vue';
export type ReactiveFunction<TParam> = () => TParam;

export const CustomerTicketsByFilterDocument = gql`
    query customerTicketsByFilter($customerId: ID, $customerOrganizations: Boolean, $stateTypeCategory: EnumTicketStateTypeCategory, $pageSize: Int = 7, $cursor: String) {
  ticketsByFilter(
    customerId: $customerId
    customerOrganizations: $customerOrganizations
    stateTypeCategory: $stateTypeCategory
    first: $pageSize
    after: $cursor
  ) {
    totalCount
    edges {
      node {
        id
        internalId
        number
        title
        stateColorCode
        state {
          id
          name
        }
        createdAt
      }
    }
    pageInfo {
      endCursor
    }
  }
}
    `;
export function useCustomerTicketsByFilterQuery(variables: Types.CustomerTicketsByFilterQueryVariables | VueCompositionApi.Ref<Types.CustomerTicketsByFilterQueryVariables> | ReactiveFunction<Types.CustomerTicketsByFilterQueryVariables> = {}, options: VueApolloComposable.UseQueryOptions<Types.CustomerTicketsByFilterQuery, Types.CustomerTicketsByFilterQueryVariables> | VueCompositionApi.Ref<VueApolloComposable.UseQueryOptions<Types.CustomerTicketsByFilterQuery, Types.CustomerTicketsByFilterQueryVariables>> | ReactiveFunction<VueApolloComposable.UseQueryOptions<Types.CustomerTicketsByFilterQuery, Types.CustomerTicketsByFilterQueryVariables>> = {}) {
  return VueApolloComposable.useQuery<Types.CustomerTicketsByFilterQuery, Types.CustomerTicketsByFilterQueryVariables>(CustomerTicketsByFilterDocument, variables, options);
}
export function useCustomerTicketsByFilterLazyQuery(variables: Types.CustomerTicketsByFilterQueryVariables | VueCompositionApi.Ref<Types.CustomerTicketsByFilterQueryVariables> | ReactiveFunction<Types.CustomerTicketsByFilterQueryVariables> = {}, options: VueApolloComposable.UseQueryOptions<Types.CustomerTicketsByFilterQuery, Types.CustomerTicketsByFilterQueryVariables> | VueCompositionApi.Ref<VueApolloComposable.UseQueryOptions<Types.CustomerTicketsByFilterQuery, Types.CustomerTicketsByFilterQueryVariables>> | ReactiveFunction<VueApolloComposable.UseQueryOptions<Types.CustomerTicketsByFilterQuery, Types.CustomerTicketsByFilterQueryVariables>> = {}) {
  return VueApolloComposable.useLazyQuery<Types.CustomerTicketsByFilterQuery, Types.CustomerTicketsByFilterQueryVariables>(CustomerTicketsByFilterDocument, variables, options);
}
export type CustomerTicketsByFilterQueryCompositionFunctionResult = VueApolloComposable.UseQueryReturn<Types.CustomerTicketsByFilterQuery, Types.CustomerTicketsByFilterQueryVariables>;