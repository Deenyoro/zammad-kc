// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import type { ComputedRef, Ref } from 'vue'

export interface TicketBulkEditReturn {
  bulkEditActive: ComputedRef<boolean>
  checkedItemIds: Ref<Set<ID>>
  setOnSuccessCallback: (callback: () => void) => void
  onSuccessCallback?: () => void
  openBulkEditFlyout: () => void
}

export interface TicketBulkEditOptions {
  onSuccess?: () => void
}
