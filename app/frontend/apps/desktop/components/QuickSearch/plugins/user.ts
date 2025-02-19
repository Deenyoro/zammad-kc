// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import User from '../entitites/User.vue'

import type { QuickSearchPlugin } from '../types.ts'

export default <QuickSearchPlugin>{
  name: 'User',
  component: User,
  priority: 200,
  searchResultKey: 'quickSearchUsers',
  searchResultLabel: __('Found users'),
}
