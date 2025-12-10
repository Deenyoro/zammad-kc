// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { ApolloLink } from '@apollo/client/core'
import { getMainDefinition } from '@apollo/client/utilities'

import log from '#shared/utils/log.ts'

import type { Operation, OperationVariables } from '@apollo/client/core'

const skipSubscriptionStore = new Map<string, OperationVariables[]>()

const checkAndRemoveSkipEntry = (operation: Operation): boolean => {
  const { operationName } = operation
  const context = operation.getContext()
  const callback = context.skipSubscriptionCallback

  const variablesArray = skipSubscriptionStore.get(operationName)
  if (!variablesArray || variablesArray.length === 0) return false

  // Check if any variables match the callback and remove them
  const remainingVariables = variablesArray.filter((variables) => !callback(variables))
  const shouldSkip = remainingVariables.length !== variablesArray.length

  if (remainingVariables.length === 0) {
    skipSubscriptionStore.delete(operationName)
  } else {
    skipSubscriptionStore.set(operationName, remainingVariables)
  }

  if (shouldSkip && log.getLevel() <= log.levels.DEBUG) {
    log.debug(`[SkipSubscription] Skipped: ${operationName}`)
  }

  return shouldSkip
}

const skipSubscriptionResultLink = new ApolloLink((operation, forward) => {
  const definition = getMainDefinition(operation.query)

  if (definition.kind !== 'OperationDefinition') {
    return forward(operation)
  }

  // For mutations and queries, check if some subscription should be added to skip store.
  if (definition.operation === 'mutation' || definition.operation === 'query') {
    const context = operation.getContext()

    if (context.skipSubscription) {
      // Check if we should add these variables to the skip store
      const shouldAdd =
        !context.skipSubscriptionAddCallback ||
        context.skipSubscriptionAddCallback(operation.variables || {})

      if (shouldAdd) {
        const existingVariables = skipSubscriptionStore.get(context.skipSubscription) || []
        existingVariables.push(operation.variables || {})
        skipSubscriptionStore.set(context.skipSubscription, existingVariables)
      }
    }

    return forward(operation)
  }

  // For subscriptions, check if result should be skipped in response phase
  if (definition.operation === 'subscription') {
    return forward(operation).filter(() => {
      const shouldSkip = checkAndRemoveSkipEntry(operation)

      return !shouldSkip
    })
  }

  return forward(operation)
})

export default skipSubscriptionResultLink

// Export helper function for external use
export const clearSkipSubscriptionStore = (): void => {
  skipSubscriptionStore.clear()
}
