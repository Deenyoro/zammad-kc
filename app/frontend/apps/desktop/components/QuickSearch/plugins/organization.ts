// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import Organization from '../entitites/Organization.vue'

import type { QuickSearchPlugin } from '../types.ts'

export default <QuickSearchPlugin>{
  name: 'Organization',
  component: Organization,
  priority: 300,
  searchResultKey: 'quickSearchOrganizations',
  searchResultLabel: __('Found organizations'),
}
