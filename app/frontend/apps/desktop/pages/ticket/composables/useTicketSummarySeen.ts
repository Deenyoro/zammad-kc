// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { useLocalStorage } from '@vueuse/core'
import { readonly, ref, watch, computed } from 'vue'

import type { TicketAiAssistanceSummarizePayload } from '#shared/graphql/types.ts'

import { useTicketInformation } from '#desktop/pages/ticket/composables/useTicketInformation.ts'
import { useTicketSidebar } from '#desktop/pages/ticket/composables/useTicketSidebar.ts'

const currentSummaryFingerprint = ref<
  TicketAiAssistanceSummarizePayload['fingerprintMd5'] | boolean
>()

export const useTicketSummarySeen = () => {
  const { ticket } = useTicketInformation()
  const sidebar = useTicketSidebar()

  const isTicketStateMerged = computed(
    () => ticket.value?.state.name === 'merged',
  )

  const isTicketSummarySidebarActive = computed(
    () => sidebar.activeSidebar.value === 'ticket-summary',
  )

  const localStorageFingerprint = useLocalStorage(
    `${ticket.value?.internalId}-ticket-summary-seen`,
    undefined as TicketAiAssistanceSummarizePayload['fingerprintMd5'] | boolean,
  )

  const setFingerprint = (md5Sum?: string | null | boolean) => {
    if (!md5Sum) return

    currentSummaryFingerprint.value = md5Sum

    if (!isTicketSummarySidebarActive.value) return

    localStorageFingerprint.value = md5Sum
  }

  watch(
    () => sidebar.activeSidebar.value,
    (currentSidebar) => {
      if (currentSidebar === 'ticket-summary')
        setFingerprint(currentSummaryFingerprint.value)
    },
  )

  const isCurrentTicketSummaryRead = computed(
    () => currentSummaryFingerprint.value === localStorageFingerprint.value,
  )

  return {
    localStorageFingerprint: readonly(localStorageFingerprint),
    currentSummaryFingerprint: readonly(currentSummaryFingerprint),
    isCurrentTicketSummaryRead,
    isTicketSummarySidebarActive,
    isTicketStateMerged,
    setFingerprint,
  }
}
