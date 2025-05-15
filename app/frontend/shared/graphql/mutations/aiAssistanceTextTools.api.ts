import * as Types from '#shared/graphql/types.ts';

import gql from 'graphql-tag';
import * as VueApolloComposable from '@vue/apollo-composable';
import * as VueCompositionApi from 'vue';
export type ReactiveFunction<TParam> = () => TParam;

export const AiAssistanceTextToolsDocument = gql`
    mutation aiAssistanceTextTools($input: String!, $serviceType: EnumAITextToolService!) {
  aiAssistanceTextTools(input: $input, serviceType: $serviceType) {
    output
  }
}
    `;
export function useAiAssistanceTextToolsMutation(options: VueApolloComposable.UseMutationOptions<Types.AiAssistanceTextToolsMutation, Types.AiAssistanceTextToolsMutationVariables> | ReactiveFunction<VueApolloComposable.UseMutationOptions<Types.AiAssistanceTextToolsMutation, Types.AiAssistanceTextToolsMutationVariables>> = {}) {
  return VueApolloComposable.useMutation<Types.AiAssistanceTextToolsMutation, Types.AiAssistanceTextToolsMutationVariables>(AiAssistanceTextToolsDocument, options);
}
export type AiAssistanceTextToolsMutationCompositionFunctionResult = VueApolloComposable.UseMutationReturn<Types.AiAssistanceTextToolsMutation, Types.AiAssistanceTextToolsMutationVariables>;