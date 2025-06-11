<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

import type { AsyncExecutionError, TicketAiAssistanceSummary } from '#shared/graphql/types.ts'
import type { ObjectLike } from '#shared/types/utils.ts'

import CommonButton from '#desktop/components/CommonButton/CommonButton.vue'
import TicketSidebarContent from '#desktop/pages/ticket/components/TicketSidebar/TicketSidebarContent.vue'
import SummarySkeleton from '#desktop/pages/ticket/components/TicketSidebar/TicketSidebarSummary/TicketSidebarSummary/SummarySkeleton.vue'
import TicketSummaryCreateChecklist from '#desktop/pages/ticket/components/TicketSidebar/TicketSidebarSummary/TicketSidebarSummaryContent/TicketSummaryCreateChecklist.vue'
import TicketSummaryItem from '#desktop/pages/ticket/components/TicketSidebar/TicketSidebarSummary/TicketSidebarSummaryContent/TicketSummaryItem.vue'
import {
  type SummaryItem,
  TicketSummaryFeature,
} from '#desktop/pages/ticket/components/TicketSidebar/TicketSidebarSummary/types.ts'
import type { TicketSidebarContentProps } from '#desktop/pages/ticket/types/sidebar.ts'

interface Props extends TicketSidebarContentProps {
  summary: Maybe<TicketAiAssistanceSummary>
  error: Maybe<AsyncExecutionError>
  showErrorDetails: boolean
  summaryHeadings: SummaryItem[]
  isProviderConfigured: boolean
}

const props = defineProps<Props>()

defineEmits<{
  'retry-get-summary': []
}>()

const persistentStates = defineModel<ObjectLike>({ required: true })

const errorMessage = computed(() => props.error?.message)

const noSummaryPossible = computed(() => {
  const { summary } = props

  if (!summary) return false

  return props.summaryHeadings.every((section) => !summary[section.key]?.length)
})
</script>

<template>
  <TicketSidebarContent
    v-model="persistentStates.scrollPosition"
    :icon="sidebarPlugin.icon"
    :title="sidebarPlugin.title"
    variant="ai"
  >
    <section class="space-y-4.5">
      <template v-if="!isProviderConfigured">
        <CommonAlert class="self-stretch" variant="danger">
          <div class="flex flex-col gap-1.5">
            <CommonLabel class="text-red-500 dark:text-red-500">
              {{ $t('No AI provider is currently set up. Please contact your administrator.') }}
            </CommonLabel>
          </div>
        </CommonAlert>
      </template>
      <template v-else-if="errorMessage">
        <div class="flex flex-col items-end gap-3">
          <CommonAlert class="self-stretch" variant="danger">
            <div class="flex flex-col gap-1.5">
              <CommonLabel class="text-red-500 dark:text-red-500">
                {{
                  $t(
                    'The summary could not be generated. Please try again later or contact your administrator.',
                  )
                }}
              </CommonLabel>
              <CommonLabel v-if="showErrorDetails" class="text-red-500 dark:text-red-500">
                {{ errorMessage }}
              </CommonLabel>
            </div>
          </CommonAlert>
          <CommonButton variant="tertiary" @click="$emit('retry-get-summary')">{{
            $t('Retry')
          }}</CommonButton>
        </div>
      </template>
      <template v-else-if="noSummaryPossible">
        <CommonAlert variant="info">
          {{ $t('There is not enough content yet to summarize this ticket.') }}
        </CommonAlert>
      </template>
      <template v-else-if="summary">
        <template v-for="item in summaryHeadings" :key="item.key">
          <article v-if="summary[item.key]?.length">
            <TicketSummaryCreateChecklist
              v-if="item.feature === TicketSummaryFeature.Checklist"
              :summary="summary[item.key] as string[]"
              :label="item.label"
            />
            <TicketSummaryItem v-else :summary="summary[item.key]!" :label="item.label" />
          </article>
        </template>

        <CommonLabel
          size="small"
          class="w-full border-t border-neutral-100 pt-2 text-stone-200! dark:border-gray-900 dark:text-neutral-500!"
          tag="p"
          >{{ $t('Be sure to check AI-generated summaries for accuracy.') }}
        </CommonLabel>
      </template>

      <template v-else>
        <CommonLabel size="small" class="text-stone-200! dark:text-neutral-500!" tag="p">{{
          $t('Zammad Smart Assist is generating the summary for you…')
        }}</CommonLabel>
        <SummarySkeleton v-for="n in 4" :key="n" :style="{ 'animation-delay': `${n * 0.1}s` }" />
      </template>
    </section>
  </TicketSidebarContent>
</template>
