// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

// import { offsetLimitPagination } from '@apollo/client/utilities'

import type { FieldPolicy } from '@apollo/client/cache/inmemory/policies'
import type {
  InMemoryCacheConfig,
  Reference,
} from '@apollo/client/cache/inmemory/types'

const offsetLimitPagination = (
  keyArgs: FieldPolicy<unknown>['keyArgs'] = false,
): FieldPolicy<{ totalCount: number; items: Reference[] }> => {
  return {
    keyArgs,
    merge(existing, incoming, { args }) {
      const mergedItems = existing?.items ? [...existing.items] : []

      if (incoming.items) {
        if (args) {
          // Assume an offset of 0 if args.offset omitted.
          const { offset = 0 } = args
          // TODO: Do we need to check if item already exists...? What is happening in the cursor pagination?
          for (let i = 0; i < incoming.items.length; i += 1) {
            mergedItems[offset + i] = incoming.items[i]
          }
        } else {
          throw new Error(
            // eslint-disable-next-line zammad/zammad-detect-translatable-string
            'No args provided for offset pagination.',
          )
        }
      }

      return {
        totalCount: existing?.totalCount || incoming?.totalCount || 0,
        items: mergedItems,
      }
    },
  }
}

export default function registerOffsetStylePagination(
  config: InMemoryCacheConfig,
  queryName: string,
  fields: string[],
): InMemoryCacheConfig {
  config.typePolicies ||= {}
  config.typePolicies.Query ||= {}
  config.typePolicies.Query.fields ||= {}
  config.typePolicies.Query.fields[queryName] = offsetLimitPagination(fields)

  return config
}
