// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import type { Item, QuickSearchQuery } from '#shared/graphql/types.ts'
import type { ObjectLike } from '#shared/types/utils.ts'

import type { PartialDeep } from 'type-fest'
import type { Component } from 'vue'

export type QuickSearchPlugin = {
  name: string
  component: Component
  priority: number
  searchResultKey: Exclude<keyof QuickSearchQuery, '__typename'>
  searchResultLabel: string
}

export interface QuickSearchPluginProps {
  item: ObjectLike
  mode: 'recently-viewed' | 'quick-search-results'
}

export interface QuickSearchResultData {
  component: Component
  remainingItemCount: number
  name: string
  label: string
  items: PartialDeep<Item>[]
  totalCount: number
}
