// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import mitt, { type Emitter } from 'mitt'

type StaticEvents = {
  'session-invalid': void
  'expand-collapsed-content': string
  'focus-quick-search-field': void
  'reset-quick-search-field': void
  'main-sidebar-transition': void
  'close-popover': void
  'recompute-has-reached-article-bottom': void
  'websocket-open': void
  'websocket-close': void
  reconnected: void
}

type DynamicEvents = {
  [key in `customer-ticket-list-refetch:${string}`]: void
}

export type Events = StaticEvents & DynamicEvents

const emitter: Emitter<Events> = mitt<Events>()

export default emitter
