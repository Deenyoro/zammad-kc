import * as Types from '#shared/graphql/types.ts';

import gql from 'graphql-tag';
import * as VueApolloComposable from '@vue/apollo-composable';
import * as VueCompositionApi from 'vue';
export type ReactiveFunction<TParam> = () => TParam;

export const TicketAiAssistanceSummaryUpdatesDocument = gql`
    subscription ticketAIAssistanceSummaryUpdates($ticketId: ID!, $locale: String!) {
  ticketAIAssistanceSummaryUpdates(ticketId: $ticketId, locale: $locale) {
    summary {
      conversationSummary
      openQuestions
      problem
      suggestions
    }
    fingerprintMd5
    error {
      message
      exception
    }
  }
}
    `;
export function useTicketAiAssistanceSummaryUpdatesSubscription(variables: Types.TicketAiAssistanceSummaryUpdatesSubscriptionVariables | VueCompositionApi.Ref<Types.TicketAiAssistanceSummaryUpdatesSubscriptionVariables> | ReactiveFunction<Types.TicketAiAssistanceSummaryUpdatesSubscriptionVariables>, options: VueApolloComposable.UseSubscriptionOptions<Types.TicketAiAssistanceSummaryUpdatesSubscription, Types.TicketAiAssistanceSummaryUpdatesSubscriptionVariables> | VueCompositionApi.Ref<VueApolloComposable.UseSubscriptionOptions<Types.TicketAiAssistanceSummaryUpdatesSubscription, Types.TicketAiAssistanceSummaryUpdatesSubscriptionVariables>> | ReactiveFunction<VueApolloComposable.UseSubscriptionOptions<Types.TicketAiAssistanceSummaryUpdatesSubscription, Types.TicketAiAssistanceSummaryUpdatesSubscriptionVariables>> = {}) {
  return VueApolloComposable.useSubscription<Types.TicketAiAssistanceSummaryUpdatesSubscription, Types.TicketAiAssistanceSummaryUpdatesSubscriptionVariables>(TicketAiAssistanceSummaryUpdatesDocument, variables, options);
}
export type TicketAiAssistanceSummaryUpdatesSubscriptionCompositionFunctionResult = VueApolloComposable.UseSubscriptionReturn<Types.TicketAiAssistanceSummaryUpdatesSubscription, Types.TicketAiAssistanceSummaryUpdatesSubscriptionVariables>;