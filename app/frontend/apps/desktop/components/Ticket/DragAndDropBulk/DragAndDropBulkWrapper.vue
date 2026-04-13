<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { useElementHover } from '@vueuse/core'
import { computed, toRef, useTemplateRef } from 'vue'

import { useMacros } from '#shared/entities/macro/composables/useMacros.ts'
import type { TicketMacrosSelectorInput } from '#shared/graphql/types.ts'

import CommonOverlayContainer from '#desktop/components/CommonOverlayContainer/CommonOverlayContainer.vue'
import type {
  TicketBulkOverviewContext,
  TicketBulkSearchContext,
} from '#desktop/components/Ticket/TicketBulkEditFlyout/useTicketBulkEdit.ts'
import { useTicketBulkUpdateStore } from '#desktop/entities/user/current/stores/ticketBulkUpdate.ts'

// import DragAndDropBulkBottomDrawer from './DragAndDropBulkBottomDrawer.vue'
import DragAndDropBulkConfirmation from './DragAndDropBulkConfirmation.vue'
import DragAndDropBulkCursorPreview from './DragAndDropBulkCursorPreview.vue'
import DragAndDropBulkTopDrawer from './DragAndDropBulkTopDrawer.vue'

export interface Props {
  ticketIds: Set<ID>
  groupIds: Array<ID>
  bulkContext: TicketBulkOverviewContext | TicketBulkSearchContext
  bulkCount: number
  cursorPosition: {
    x: number
    y: number
  }
}

const props = defineProps<Props>()

const macrosSelector = computed(() => {
  let selector: TicketMacrosSelectorInput = {}

  if (props.bulkCount) {
    if ('overviewId' in props.bulkContext) selector = { overviewId: props.bulkContext.overviewId }
    else if ('searchQuery' in props.bulkContext)
      selector = { searchQuery: props.bulkContext.searchQuery }
  } else selector = { entityIds: props.groupIds }

  return selector
})

const { macrosLoaded, macros } = useMacros(macrosSelector)

const bulkTopDrawerElement = useTemplateRef<HTMLElement>('bulk-top-drawer')
const bulkBottomDrawerElement = useTemplateRef<HTMLElement>('bulk-bottom-drawer')

const isTopBarHovered = useElementHover(bulkTopDrawerElement, {})
const isBottomBarHovered = useElementHover(bulkBottomDrawerElement, {})

const showCancel = computed(() => isTopBarHovered.value || isBottomBarHovered.value)

const confirmationPending = toRef(useTicketBulkUpdateStore(), 'confirmationPending')
</script>

<template>
  <CommonOverlayContainer
    class="fixed top-0 isolate z-51 size-full ltr:left-0 rtl:right-0"
    :class="{ 'cursor-grabbing': !confirmationPending }"
    fullscreen
    :role="undefined"
  >
    <template v-if="confirmationPending">
      <DragAndDropBulkConfirmation
        class="absolute top-1/2 z-52 -translate-y-1/2 ltr:left-1/2 ltr:-translate-x-1/2 rtl:right-1/2 rtl:translate-x-1/2"
      />
    </template>

    <template v-else>
      <DragAndDropBulkCursorPreview :ticket-ids="ticketIds" :cursor-position="cursorPosition" />

      <DragAndDropBulkTopDrawer
        v-show="!isBottomBarHovered"
        ref="bulk-top-drawer"
        :is-active="isTopBarHovered"
        :macros-loaded="macrosLoaded"
        :macros="macros"
        class="absolute"
      />

      <transition name="fade-quick">
        <section
          v-if="showCancel"
          class="absolute flex w-full -translate-y-1/2 items-center gap-10 px-10 text-white! before:grow before:border before:border-dashed after:grow after:border after:border-dashed ltr:left-1/2 ltr:-translate-x-1/2 rtl:right-1/2 rtl:translate-x-1/2"
          :class="{
            'top-[calc(50%+7.5rem)]': isTopBarHovered, // 13 rem is the total height of both drawers -> 7.5 is the half
            'top-[calc(50%-7.5rem)]': isBottomBarHovered,
          }"
        >
          <div class="flex flex-col items-center gap-12">
            <CommonIcon name="arrow-down-short" />
            <CommonLabel class="text-current!">{{ $t('Drag here to cancel') }}</CommonLabel>
            <CommonIcon name="arrow-up-short" />
          </div>
        </section>
      </transition>

      <!-- :TODO when we start the story -->
      <!-- <transition name="fade-up">
        <DragAndDropBulkBottomDrawer
          v-show="!isTopBarHovered"
          ref="bulk-bottom-drawer"
          :is-active="isBottomBarHovered"
          class="absolute bottom-0"
        />
      </transition> -->
    </template>
  </CommonOverlayContainer>
</template>
