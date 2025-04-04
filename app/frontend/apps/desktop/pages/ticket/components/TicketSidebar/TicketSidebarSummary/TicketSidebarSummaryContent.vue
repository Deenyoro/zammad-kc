<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

import type {
  AsyncExecutionError,
  TicketAiAssistanceSummary,
} from '#shared/graphql/types.ts'
import type { ObjectLike } from '#shared/types/utils.ts'

import CommonButton from '#desktop/components/CommonButton/CommonButton.vue'
import TicketSidebarContent from '#desktop/pages/ticket/components/TicketSidebar/TicketSidebarContent.vue'
import SummarySkeleton from '#desktop/pages/ticket/components/TicketSidebar/TicketSidebarSummary/TicketSidebarSummary/SummarySkeleton.vue'
import { useTicketSummary } from '#desktop/pages/ticket/composables/useTicketSummary.ts'
import type { TicketSidebarContentProps } from '#desktop/pages/ticket/types/sidebar.ts'

interface Props extends TicketSidebarContentProps {
  summary: Maybe<TicketAiAssistanceSummary>
  error: Maybe<AsyncExecutionError>
  showErrorDetails: boolean
}

const props = defineProps<Props>()

defineEmits<{
  'retry-get-summary': []
}>()

const persistentStates = defineModel<ObjectLike>({ required: true })

const { summaryHeadings, isProviderConfigured } = useTicketSummary()

const errorMessage = computed(() => props.error?.message)

const noSummaryPossible = computed(() => {
  const { summary } = props

  if (!summary) return false

  return summaryHeadings.value.every((section) => !summary[section.key]?.length)
})
</script>

<template>
  <TicketSidebarContent
    v-model="persistentStates.scrollPosition"
    :icon="sidebarPlugin.icon"
    :title="sidebarPlugin.title"
  >
    <section class="space-y-6">
      <template v-if="!isProviderConfigured">
        <CommonAlert class="self-stretch" variant="danger">
          <div class="flex flex-col gap-1.5">
            <CommonLabel class="text-red-500 dark:text-red-500">
              {{
                $t(
                  'No AI provider is currently set up. Please contact your administrator.',
                )
              }}
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
              <CommonLabel
                v-if="showErrorDetails"
                class="text-red-500 dark:text-red-500"
              >
                {{ errorMessage }}
              </CommonLabel>
            </div>
          </CommonAlert>
          <CommonButton
            variant="tertiary"
            @click="$emit('retry-get-summary')"
            >{{ $t('Retry') }}</CommonButton
          >
        </div>
      </template>
      <template v-else-if="noSummaryPossible">
        <CommonAlert variant="info">
          {{ $t('There is not enough content yet to summarize this ticket.') }}
        </CommonAlert>
      </template>
      <template v-else-if="props.summary">
        <template v-for="heading in summaryHeadings" :key="heading.key">
          <article v-if="props.summary[heading.key]?.length">
            <CommonLabel
              class="mb-3 block! text-black! dark:text-white!"
              tag="h3"
              >{{ heading.label }}
            </CommonLabel>
            <ol
              v-if="Array.isArray(props.summary[heading.key])"
              class="space-y-1 text-gray-100 dark:text-neutral-400"
            >
              <li
                v-for="content in props.summary[heading.key]"
                :key="content"
                class="flex gap-2 ps-2 before:mt-1.5 before:h-[3px] before:w-[3px] before:shrink-0 before:rounded-full before:bg-current"
              >
                <CommonLabel tag="p">{{ content }}</CommonLabel>
              </li>
            </ol>
            <CommonLabel v-else tag="p"
              >{{ props.summary[heading.key] }}
            </CommonLabel>
          </article>
        </template>

        <CommonLabel
          size="small"
          class="text-stone-200! dark:text-neutral-500!"
          tag="p"
          >{{ $t('*Be sure to check AI-generated summaries for accuracy') }}
        </CommonLabel>
      </template>

      <template v-else>
        <CommonLabel
          size="small"
          class="text-stone-200! dark:text-neutral-500!"
          tag="p"
          >{{
            $t('Zammad Smart Assist is generating the summary for you…')
          }}</CommonLabel
        >
        <SummarySkeleton
          v-for="n in 4"
          :key="n"
          :style="{ 'animation-delay': `${n * 0.1}s` }"
        />
      </template>
    </section>
  </TicketSidebarContent>
</template>
