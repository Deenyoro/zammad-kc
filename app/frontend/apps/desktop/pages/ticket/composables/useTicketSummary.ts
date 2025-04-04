// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/
import { storeToRefs } from 'pinia'
import { computed } from 'vue'

import { useApplicationStore } from '#shared/stores/application.ts'

import type {
  SummaryConfig,
  SummaryItem,
} from '#desktop/pages/ticket/components/TicketSidebar/TicketSidebarSummary/types.ts'
import { useTicketInformation } from '#desktop/pages/ticket/composables/useTicketInformation.ts'

export const useTicketSummary = () => {
  const { config } = storeToRefs(useApplicationStore())

  const summaryConfig = computed(
    () => config.value.ai_assistance_ticket_summary_config as SummaryConfig,
  )

  const isProviderConfigured = computed(() => !!config.value.ai_provider)

  const { ticket } = useTicketInformation()

  const isEnabled = computed(
    () =>
      !!(
        ticket.value &&
        ticket.value?.state.name !== 'merged' &&
        config.value.ai_assistance_ticket_summary
      ),
  )

  const headings = computed<SummaryItem[]>(() => [
    {
      key: 'problem',
      label: __('Customer Intent'),
      active: true,
    },
    {
      key: 'conversationSummary',
      label: __('Conversation Summary'),
      active: true,
    },
    {
      key: 'openQuestions',
      label: __('Open Questions'),
      active: summaryConfig.value.open_questions,
    },
    {
      key: 'suggestions',
      label: __('Suggested Next Steps'),
      active: summaryConfig.value.suggestions,
    },
  ])

  const summaryHeadings = computed(() =>
    headings.value.filter((heading) => heading.active),
  )

  return { isEnabled, isProviderConfigured, summaryHeadings }
}
