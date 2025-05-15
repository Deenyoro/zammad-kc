import * as Types from '#shared/graphql/types.ts';

import * as Mocks from '#tests/graphql/builders/mocks.ts'
import * as Operations from './aiAssistanceTextTools.api.ts'
import * as ErrorTypes from '#shared/types/error.ts'

export function mockAiAssistanceTextToolsMutation(defaults: Mocks.MockDefaultsValue<Types.AiAssistanceTextToolsMutation, Types.AiAssistanceTextToolsMutationVariables>) {
  return Mocks.mockGraphQLResult(Operations.AiAssistanceTextToolsDocument, defaults)
}

export function waitForAiAssistanceTextToolsMutationCalls() {
  return Mocks.waitForGraphQLMockCalls<Types.AiAssistanceTextToolsMutation>(Operations.AiAssistanceTextToolsDocument)
}

export function mockAiAssistanceTextToolsMutationError(message: string, extensions: {type: ErrorTypes.GraphQLErrorTypes }) {
  return Mocks.mockGraphQLResultWithError(Operations.AiAssistanceTextToolsDocument, message, extensions);
}
