// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import mitt, { type Emitter } from 'mitt'

type Events = {
  sessionInvalid: void
  'expand-collapsed-content': string
}

const emitter: Emitter<Events> = mitt<Events>()

export default emitter
