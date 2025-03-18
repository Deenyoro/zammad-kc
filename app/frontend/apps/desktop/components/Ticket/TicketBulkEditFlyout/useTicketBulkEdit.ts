// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { computed, inject, provide, ref } from 'vue'

import { useSessionStore } from '#shared/stores/session.ts'

import { useFlyout } from '../../CommonFlyout/useFlyout.ts'

import type { TicketBulkEditReturn } from './types.ts'

const TICKET_BULK_EDIT_SYMBOL = Symbol('ticket-bulk-edit')

export const useTicketBulkEdit = () => {
  const injectBulkEdit = inject<Maybe<TicketBulkEditReturn>>(
    TICKET_BULK_EDIT_SYMBOL,
    null,
  )

  if (injectBulkEdit) return injectBulkEdit

  const checkedItemIds = ref<Set<ID>>(new Set())

  const { hasPermission } = useSessionStore()

  const bulkEditActive = computed(() => hasPermission('ticket.agent'))

  let onSuccessCallback: (() => void) | undefined

  const { open } = useFlyout({
    name: 'tickets-bulk-edit',
    component: () =>
      import(
        '#desktop/components/Ticket/TicketBulkEditFlyout/TicketBulkEditFlyout.vue'
      ),
  })

  const openBulkEditFlyout = () => {
    open({
      ticketIds: checkedItemIds,
      onSuccess: () => {
        checkedItemIds.value.clear()
        onSuccessCallback?.()
      },
    })
  }

  const provideBulkEdit = {
    bulkEditActive,
    checkedItemIds,
    openBulkEditFlyout,
    setOnSuccessCallback: (callback: () => void) => {
      onSuccessCallback = callback
    },
    onSuccessCallback,
  }

  provide(TICKET_BULK_EDIT_SYMBOL, provideBulkEdit)

  return provideBulkEdit
}
