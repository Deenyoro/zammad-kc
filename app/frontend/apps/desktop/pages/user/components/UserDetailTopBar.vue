<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { useElementSize } from '@vueuse/core'
import { computed, toRef, useTemplateRef, type Ref } from 'vue'

import type { User } from '#shared/graphql/types.ts'

import { useElementScroll } from '#desktop/composables/useElementScroll.ts'
import { useTopBarHeaderHover } from '#desktop/composables/useTopBarHeaderHover.ts'
import TopBarHeader from '#desktop/pages/user/components/UserDetailTopBar/TopBarHeader.vue'

interface Props {
  user: User
  userDisplayName: string
  contentContainerElement: HTMLElement | null
}

const props = defineProps<Props>()

const headerElement = useTemplateRef('header')

const { height: headerHeight } = useElementSize(headerElement, undefined, {
  box: 'border-box',
})

const { width } = useElementSize(toRef(props, 'contentContainerElement'))
const { y } = useElementScroll(toRef(props, 'contentContainerElement') as Ref<HTMLDivElement>)

const { containerEventHandlers, isHovering } = useTopBarHeaderHover([headerElement])

const containerWidth = computed(() => (width.value ? `${width.value}px` : 'auto'))

// Show the header earlier to always have it visible
const NEGATIVE_PADDING = -30

const absoluteContainerOffset = computed(() => {
  const offset = y.value - (headerHeight.value + NEGATIVE_PADDING)
  return `${offset > 0 ? 0 : offset}px`
})

const stickyContainerTop = computed(() => {
  if (isHovering.value) return '0px'
  if (y.value < headerHeight.value) return `-${y.value}px`
  return `-${headerHeight.value}px`
})
</script>

<template>
  <TopBarHeader
    class="absolute top-0 right-0 left-0 z-30 bg-neutral-50/80 backdrop-blur-2xs dark:bg-gray-500/80"
    :class="{ '-z-10! opacity-0': isHovering }"
    aria-hidden="true"
    :hide-details="true"
    :user="user"
    :user-display-name="userDisplayName"
    data-test-id="user-detail-top-bar-clipped-details"
    :style="{
      transform: `translateY(${absoluteContainerOffset})`,
      width: containerWidth,
    }"
    v-on="containerEventHandlers"
  />

  <TopBarHeader
    ref="header"
    class="sticky top-0 right-0 left-0 z-20 w-full bg-neutral-50/80 backdrop-blur-2xs dark:bg-gray-500/80"
    :class="{ 'transition-[top]': isHovering }"
    :hide-details="false"
    :user="user"
    :user-display-name="userDisplayName"
    data-test-id="user-detail-top-bar"
    :style="{
      top: stickyContainerTop,
    }"
    v-on="containerEventHandlers"
  />
</template>
