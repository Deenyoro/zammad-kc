import * as Types from '#shared/graphql/types.ts';

import gql from 'graphql-tag';
import { ErrorsFragmentDoc } from '../../../../../../../shared/graphql/fragments/errors.api';
import * as VueApolloComposable from '@vue/apollo-composable';
import * as VueCompositionApi from 'vue';
export type ReactiveFunction<TParam> = () => TParam;

export const UserCurrentTicketSummaryBannerHiddenDocument = gql`
    mutation userCurrentTicketSummaryBannerHidden($hidden: Boolean!) {
  userCurrentTicketSummaryBannerHidden(hidden: $hidden) {
    errors {
      ...errors
    }
    success
  }
}
    ${ErrorsFragmentDoc}`;
export function useUserCurrentTicketSummaryBannerHiddenMutation(options: VueApolloComposable.UseMutationOptions<Types.UserCurrentTicketSummaryBannerHiddenMutation, Types.UserCurrentTicketSummaryBannerHiddenMutationVariables> | ReactiveFunction<VueApolloComposable.UseMutationOptions<Types.UserCurrentTicketSummaryBannerHiddenMutation, Types.UserCurrentTicketSummaryBannerHiddenMutationVariables>> = {}) {
  return VueApolloComposable.useMutation<Types.UserCurrentTicketSummaryBannerHiddenMutation, Types.UserCurrentTicketSummaryBannerHiddenMutationVariables>(UserCurrentTicketSummaryBannerHiddenDocument, options);
}
export type UserCurrentTicketSummaryBannerHiddenMutationCompositionFunctionResult = VueApolloComposable.UseMutationReturn<Types.UserCurrentTicketSummaryBannerHiddenMutation, Types.UserCurrentTicketSummaryBannerHiddenMutationVariables>;