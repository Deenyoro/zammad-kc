// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import Ticket from '../entitites/Ticket.vue'

import type { QuickSearchPlugin } from '../types.ts'

export default <QuickSearchPlugin>{
  name: 'Ticket',
  component: Ticket,
  priority: 100,
  searchResultKey: 'quickSearchTickets',
  searchResultLabel: __('Found tickets'),
}
