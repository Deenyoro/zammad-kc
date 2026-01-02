// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

export interface CollapseOptions {
  storageKey?: string
  name?: string
}

export interface CollapseEmit {
  (event: 'collapse', arg: boolean): void
  (event: 'expand', arg: boolean): void
}
