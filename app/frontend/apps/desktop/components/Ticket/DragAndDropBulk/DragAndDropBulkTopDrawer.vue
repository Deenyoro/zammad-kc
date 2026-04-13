<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { useEventListener } from '@vueuse/core'
import { useIntervalFn, whenever, type Pausable } from '@vueuse/shared'
import { computed, ref, useTemplateRef } from 'vue'

import type { Macro } from '#shared/graphql/types.ts'

import BulkAvatarSkeleton from './components/BulkAvatarSkeleton.vue'
import ScrollButton from './components/ScrollButton.vue'
import DragAndDropBulkEntityCard from './DragAndDropBulkEntityCard.vue'
import { DragAndDropBulkEntityType } from './types.ts'

defineProps<{
  isActive: boolean
  macrosLoaded: boolean
  macros?: Pick<Macro, 'id' | 'name'>[]
}>()

const scrollContainer = useTemplateRef('scroll-container')

// The scroll step is based on the width of the card plus the gap between the cards.
const SCROLL_STEP = 116 + 28

// The counter to keep track of how long the user has been scrolling.
//   The longer the user scrolls, the faster the scrolling gets.
//   We also use this counter to recompute the display of scroll buttons.
const scrollCounter = ref(1)

const showScrollButtonStart = computed(() => {
  if (!scrollContainer.value || !scrollCounter.value) return false

  return scrollContainer.value.scrollLeft > 0
})

const showScrollButtonEnd = computed(() => {
  if (!scrollContainer.value || !scrollCounter.value) return false

  return (
    scrollContainer.value.scrollLeft + scrollContainer.value.clientWidth <
    scrollContainer.value.scrollWidth
  )
})

let scrollIntervalFn: Pausable

const scrollInterval = ref(500)

const scrollByStep = (scrollAmount: number) => {
  if (!scrollContainer.value) return

  scrollContainer.value.scrollBy({ left: scrollAmount, behavior: 'smooth' })
  scrollCounter.value += 1

  if (scrollCounter.value < 5) return

  // If the user has been scrolling for a while, speed up the scrolling.
  scrollInterval.value = 100
}

const stopScroll = () => {
  if (!scrollIntervalFn?.isActive.value) return

  scrollIntervalFn.pause()
  scrollCounter.value = 1
  scrollInterval.value = 500
}

const beginScroll = (direction: 'start' | 'end') => {
  if (!scrollContainer.value) return

  stopScroll()

  const scrollAmount = direction === 'start' ? -SCROLL_STEP : SCROLL_STEP

  scrollIntervalFn = useIntervalFn(() => scrollByStep(scrollAmount), scrollInterval, {
    immediateCallback: true,
  })
}

// Stop scrolling when mouse cursor leaves the page.
useEventListener(document, 'mouseleave', stopScroll)

whenever(
  () => !showScrollButtonStart.value || !showScrollButtonEnd.value,
  () => {
    stopScroll()
  },
)
</script>

<template>
  <div class="w-full">
    <BulkAvatarSkeleton v-if="!macrosLoaded" />

    <transition v-else mode="out-in" name="fade-down">
      <header
        v-if="!isActive && macros?.length"
        class="flex w-full items-center justify-center py-3"
      >
        <DragAndDropBulkEntityCard
          circle
          :entity-type="DragAndDropBulkEntityType.Macro"
          :label="$t('Run macro')"
        />
      </header>

      <header
        v-else-if="macros?.length"
        class="relative grid w-full grid-rows-[repeat(2,auto)] justify-center gap-3 bg-blue-200 py-3 dark:bg-gray-500"
      >
        <ScrollButton
          v-if="showScrollButtonStart"
          direction="start"
          @scroll-start="beginScroll"
          @scroll-stop="stopScroll"
        />
        <ScrollButton
          v-if="showScrollButtonEnd"
          direction="end"
          @scroll-start="beginScroll"
          @scroll-stop="stopScroll"
        />
        <ul
          ref="scroll-container"
          class="scroll-bar-hidden flex snap-x flex-row gap-7 overflow-x-auto px-28.5 py-2"
        >
          <li
            v-for="macro in macros"
            :id="macro.id"
            :key="macro.id"
            class="snap-center"
            :data-type="DragAndDropBulkEntityType.Macro"
          >
            <DragAndDropBulkEntityCard
              :label="macro.name"
              :entity-type="DragAndDropBulkEntityType.Macro"
            />
          </li>
        </ul>

        <CommonLabel class="row-start-2 block! text-center" tag="h3">{{
          $t('Run macro')
        }}</CommonLabel>
      </header>

      <header v-else class="z-53 flex h-48 w-full items-center justify-center">
        <CommonLabel class="text-white!">{{
          $t('No macros available for selected tickets')
        }}</CommonLabel>
      </header>
    </transition>
  </div>
</template>
