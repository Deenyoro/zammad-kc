import * as Types from '#shared/graphql/types.ts';

import gql from 'graphql-tag';
import * as VueApolloComposable from '@vue/apollo-composable';
import * as VueCompositionApi from 'vue';
export type ReactiveFunction<TParam> = () => TParam;

export const TicketAiAssistanceSummarizeDocument = gql`
    mutation ticketAIAssistanceSummarize($ticketId: ID!) {
  ticketAIAssistanceSummarize(ticketId: $ticketId) {
    summary {
      conversationSummary
      openQuestions
      problem
      suggestions
    }
    fingerprintMd5
    relevantForCurrentUser
  }
}
    `;
export function useTicketAiAssistanceSummarizeMutation(options: VueApolloComposable.UseMutationOptions<Types.TicketAiAssistanceSummarizeMutation, Types.TicketAiAssistanceSummarizeMutationVariables> | ReactiveFunction<VueApolloComposable.UseMutationOptions<Types.TicketAiAssistanceSummarizeMutation, Types.TicketAiAssistanceSummarizeMutationVariables>> = {}) {
  return VueApolloComposable.useMutation<Types.TicketAiAssistanceSummarizeMutation, Types.TicketAiAssistanceSummarizeMutationVariables>(TicketAiAssistanceSummarizeDocument, options);
}
export type TicketAiAssistanceSummarizeMutationCompositionFunctionResult = VueApolloComposable.UseMutationReturn<Types.TicketAiAssistanceSummarizeMutation, Types.TicketAiAssistanceSummarizeMutationVariables>;