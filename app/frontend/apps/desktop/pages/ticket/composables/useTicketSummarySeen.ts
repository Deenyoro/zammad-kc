// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { useLocalStorage } from '@vueuse/core'
import { readonly, ref, watch, computed } from 'vue'

import { useTicketInformation } from '#desktop/pages/ticket/composables/useTicketInformation.ts'
import { useTicketSidebar } from '#desktop/pages/ticket/composables/useTicketSidebar.ts'

const ticketSummaryFingerprints = ref<Map<ID, string | null | undefined>>(
  new Map(),
)

export const useTicketSummarySeen = () => {
  const { ticket, ticketInternalId } = useTicketInformation()
  const sidebar = useTicketSidebar()

  const isTicketStateMerged = computed(
    () => ticket.value?.state.name === 'merged',
  )

  const isTicketSummarySidebarActive = computed(
    () => sidebar.activeSidebar.value === 'ticket-summary',
  )

  const localStorageFingerprint = useLocalStorage<null | string>(
    `ticket-summary-seen-${ticketInternalId.value}`,
    null,
  )

  const storedSummaryFingerprint = computed<string | null>(() =>
    // NB: Compatibility layer for the legacy `App.LocalStorage` class.
    JSON.parse(localStorageFingerprint.value || 'null'),
  )

  const setFingerprint = (md5Sum?: string | null) => {
    if (!ticket.value) return

    ticketSummaryFingerprints.value.set(ticket.value.id, md5Sum)
  }

  const currentSummaryFingerprint = computed(() => {
    if (!ticket.value) return

    return ticketSummaryFingerprints.value.get(ticket.value.id)
  })

  const storeFingerprint = (md5Sum?: string | null) => {
    if (!md5Sum || localStorageFingerprint.value === md5Sum) return

    // NB: Compatibility layer for the legacy `App.LocalStorage` class.
    localStorageFingerprint.value = JSON.stringify(md5Sum)
  }

  watch(
    () => sidebar.activeSidebar.value,
    (currentSidebar) => {
      if (currentSidebar !== 'ticket-summary') return

      storeFingerprint(currentSummaryFingerprint.value)
      setFingerprint(currentSummaryFingerprint.value)
    },
  )

  const isCurrentTicketSummaryRead = computed(() =>
    !currentSummaryFingerprint.value
      ? false
      : currentSummaryFingerprint.value === storedSummaryFingerprint.value,
  )

  return {
    currentSummaryFingerprint: readonly(currentSummaryFingerprint),
    isCurrentTicketSummaryRead,
    isTicketSummarySidebarActive,
    isTicketStateMerged,
    setFingerprint,
    storeFingerprint,
  }
}
