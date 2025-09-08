// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { onBeforeUnmount } from 'vue'

import emitter, { type Events } from '#shared/utils/emitter.ts'

export const useOnEmitter = <K extends keyof Events>(
  name: K,
  callback: (payload: Events[K]) => void,
) => {
  emitter.on(name, callback)

  onBeforeUnmount(() => {
    emitter.off(name, callback)
  })
}
