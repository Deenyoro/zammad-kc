<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { ref, effectScope, watch, type EffectScope, computed } from 'vue'

import { useTicketArticleUpdatesSubscription } from '#shared/entities/ticket/graphql/subscriptions/ticketArticlesUpdates.api.ts'
import type {
  AsyncExecutionError,
  TicketAiAssistanceSummary,
} from '#shared/graphql/types.ts'
import {
  MutationHandler,
  SubscriptionHandler,
} from '#shared/server/apollo/handler/index.ts'
import { useApplicationStore } from '#shared/stores/application.ts'
import { useSessionStore } from '#shared/stores/session.ts'

import { useReactivate } from '#desktop/composables/useReactivate.ts'
import TicketSidebarSummaryContent from '#desktop/pages/ticket/components/TicketSidebar/TicketSidebarSummary/TicketSidebarSummaryContent.vue'
import { usePersistentStates } from '#desktop/pages/ticket/composables/usePersistentStates.ts'
import { useTicketInformation } from '#desktop/pages/ticket/composables/useTicketInformation.ts'
import { useTicketSummary } from '#desktop/pages/ticket/composables/useTicketSummary.ts'
import { useTicketAiAssistanceSummarizeMutation } from '#desktop/pages/ticket/graphql/mutations/ticketAIAssistanceSummarize.api.ts'
import { useTicketAiAssistanceSummaryUpdatesSubscription } from '#desktop/pages/ticket/graphql/subscriptions/ticketAIAssistanceSummaryUpdates.api.ts'
import type {
  TicketSidebarEmits,
  TicketSidebarProps,
} from '#desktop/pages/ticket/types/sidebar.ts'

import TicketSidebarWrapper from '../TicketSidebarWrapper.vue'

defineProps<TicketSidebarProps>()

const { user, hasPermission } = useSessionStore()
const { config } = useApplicationStore()

const { persistentStates } = usePersistentStates()

const emit = defineEmits<TicketSidebarEmits>()

const { ticketId } = useTicketInformation()

const { isEnabled, isProviderConfigured } = useTicketSummary()

const summary = ref<TicketAiAssistanceSummary | null>(null)
const generationError = ref<AsyncExecutionError | null>(null)

const showErrorDetails = computed(() => hasPermission('admin'))

let activeDetachedChildScope: EffectScope

const ticketSummaryHandler = new MutationHandler(
  useTicketAiAssistanceSummarizeMutation(),
)

const getAIAssistanceSummary = () => {
  if (!isProviderConfigured.value) return

  ticketSummaryHandler.send({ ticketId: ticketId.value }).then((data) => {
    summary.value = data?.ticketAIAssistanceSummarize?.summary ?? null

    // Reset error if summary is returned.
    if (summary.value) generationError.value = null
  })
}

const activateSubscription = () => {
  const articleSubscription = new SubscriptionHandler(
    useTicketArticleUpdatesSubscription(
      () => ({
        ticketId: ticketId.value,
      }),
      () => ({
        enabled: isProviderConfigured.value,
      }),
    ),
  )

  articleSubscription.onSubscribed().then(() => {
    articleSubscription.onResult(({ data }) => {
      const isNewArticle = data?.ticketArticleUpdates.addArticle

      if (!isNewArticle || isNewArticle?.sender?.name === 'System') return

      getAIAssistanceSummary()
    })
  })

  const ticketSummarySubscription = new SubscriptionHandler(
    useTicketAiAssistanceSummaryUpdatesSubscription(
      {
        ticketId: ticketId.value,
        locale: user?.preferences?.locale || config.locale_default,
      },
      () => ({
        enabled: isProviderConfigured.value,
      }),
    ),
  )

  ticketSummarySubscription.onSubscribed().then(() => {
    ticketSummarySubscription.onResult(({ data }) => {
      if (!data?.ticketAIAssistanceSummaryUpdates) return

      const { summary: summaryData, error: errorData } =
        data.ticketAIAssistanceSummaryUpdates

      if (!summaryData && !errorData) return

      if (errorData) {
        generationError.value = errorData
        summary.value = null
      } else if (summaryData) {
        summary.value = summaryData
        generationError.value = null
      }
    })
  })
}

const handleDeactivate = () => {
  activeDetachedChildScope?.stop()
}

const handleActivation = () => {
  activeDetachedChildScope = effectScope(true)
  activeDetachedChildScope.run(activateSubscription)
}

useReactivate(handleActivation, handleDeactivate)

watch(
  isEnabled,
  (showSidebar) => {
    if (showSidebar) {
      activeDetachedChildScope = effectScope(true)
      activeDetachedChildScope.run(activateSubscription)

      getAIAssistanceSummary()

      emit('show')
    } else {
      emit('hide')
      activeDetachedChildScope?.stop()
    }
  },
  { immediate: true },
)
</script>

<template>
  <TicketSidebarWrapper
    :key="sidebar"
    :sidebar="sidebar"
    :sidebar-plugin="sidebarPlugin"
    :selected="selected"
  >
    <TicketSidebarSummaryContent
      v-model="persistentStates"
      :context="context"
      :sidebar-plugin="sidebarPlugin"
      :summary="summary"
      :error="generationError"
      :show-error-details="showErrorDetails"
      @retry-get-summary="getAIAssistanceSummary"
    />
  </TicketSidebarWrapper>
</template>
