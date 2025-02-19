// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import type { QuickSearchPlugin } from '../types.ts'

const plugins = import.meta.glob<QuickSearchPlugin>(
  ['./**/*.ts', '!./**/index.ts', '!./types.ts', '!./__tests__/**/*.ts'],
  {
    eager: true,
    import: 'default',
  },
)

export const quickSearchPlugins = Object.values(plugins)

export const sortedQuickSearchPlugins = quickSearchPlugins.sort(
  (a, b) => a.priority - b.priority,
)

export const lookupQuickSearchPlugin = (searchResultKey: string) =>
  sortedQuickSearchPlugins.find(
    (plugin) => plugin.searchResultKey === searchResultKey,
  )

export const lookupQuickSearchPluginComponent = (model: string) =>
  quickSearchPlugins.find((plugin) => plugin.name === model)?.component
