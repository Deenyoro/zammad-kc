// KC: Composable for managing the bulk merge flyout.
//
// Reuses the checkedTicketIds from useTicketBulkEdit (via injection) and
// provides an openBulkMergeFlyout function that launches the merge flyout
// with the currently selected ticket IDs.
//
// The merge button shows unless the kc_bulk_merge setting is explicitly false.

import { computed, inject, provide, type ComputedRef, type Ref } from 'vue'

import { useApplicationStore } from '#shared/stores/application.ts'
import { useSessionStore } from '#shared/stores/session.ts'

import { useFlyout } from '#desktop/components/CommonFlyout/useFlyout.ts'

export interface KcBulkMergeReturn {
  bulkMergeActive: ComputedRef<boolean>
  checkedTicketIds: Ref<Set<ID>>
  openBulkMergeFlyout: () => void
  setOnSuccessCallback: (callback: () => void) => void
}

const KC_BULK_MERGE_SYMBOL = Symbol('kc-bulk-merge')

export const useKcBulkMerge = (checkedTicketIds: Ref<Set<ID>>) => {
  const injected = inject<Maybe<KcBulkMergeReturn>>(KC_BULK_MERGE_SYMBOL, null)

  if (injected) return injected

  const { hasPermission } = useSessionStore()
  const { config } = useApplicationStore()

  const ticketIds = computed<ID[]>(() =>
    Array.from(checkedTicketIds.value.keys()),
  )

  // Enabled unless the setting is explicitly false (seeded as true), the
  // same rule as the legacy UI.
  const bulkMergeActive = computed(
    () => hasPermission('ticket.agent') && config.kc_bulk_merge !== false,
  )

  let onSuccessCallback: (() => void) | undefined

  const { open } = useFlyout({
    name: 'kc-tickets-bulk-merge',
    component: () => import('./KcTicketBulkMergeFlyout.vue'),
  })

  const openBulkMergeFlyout = () => {
    open({
      ticketIds,
      onSuccess: () => {
        checkedTicketIds.value.clear()
        onSuccessCallback?.()
      },
    })
  }

  const provideBulkMerge: KcBulkMergeReturn = {
    bulkMergeActive,
    checkedTicketIds,
    openBulkMergeFlyout,
    setOnSuccessCallback: (callback: () => void) => {
      onSuccessCallback = callback
    },
  }

  provide(KC_BULK_MERGE_SYMBOL, provideBulkMerge)

  return provideBulkMerge
}
