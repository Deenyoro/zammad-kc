<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { useDebounceFn, useElementHover } from '@vueuse/core'
import { computed, useAttrs, useTemplateRef, watch } from 'vue'

import CommonUserAvatar from '#shared/components/CommonUserAvatar/CommonUserAvatar.vue'
import type { AvatarUser } from '#shared/components/CommonUserAvatar/types.ts'

import { DragAndDropBulkEntityType } from './types.ts'

export interface Props {
  label: string
  entity?: AvatarUser
  entityType: DragAndDropBulkEntityType
  circle?: boolean
}

const props = defineProps<Props>()

const emit = defineEmits<{
  'go-inside-group': [ID]
}>()

const attrs = useAttrs()

const borderClass = 'border-2 border-dashed border-stone-200 dark:border-neutral-500'

const circleClass = computed(() =>
  props.circle
    ? `rounded-full items-center justify-center size-40 bg-blue-200 dark:bg-gray-500 ${borderClass}`
    : 'rounded-lg',
)
const hoverClass = computed(() =>
  props.circle
    ? ''
    : `${borderClass} hover:bg-blue-600 hover:dark:bg-blue-900 hover:border-blue-800`,
)

const iconContainerClass = computed(() => {
  if (props.entityType === DragAndDropBulkEntityType.Macro) return 'bg-yellow-300'
  if (props.entityType === DragAndDropBulkEntityType.Ticket) return 'bg-green-500'
  return ''
})

const insideGroupElement = useTemplateRef('inside-group')

const isInsideGroupHovered = useElementHover(insideGroupElement)

watch(isInsideGroupHovered, (hovered) => {
  if (hovered) {
    useDebounceFn(() => {
      emit('go-inside-group', attrs.id as ID)
    }, 200)
  }
})
</script>

<template>
  <div class="flex flex-col" :class="[circleClass]">
    <figure
      class="flex size-full flex-col items-center justify-center gap-2 rounded-lg p-4"
      :class="[hoverClass, entityType === DragAndDropBulkEntityType.Ticket ? 'rounded-b-none' : '']"
    >
      <div
        class="flex size-20 items-center justify-center rounded-lg p-2 text-black"
        :class="iconContainerClass"
      >
        <CommonUserAvatar
          v-if="entity && entityType === DragAndDropBulkEntityType.Ticket"
          :entity="entity"
        />
        <CommonIcon
          v-else-if="entityType === DragAndDropBulkEntityType.Ticket"
          name="people-fill"
        />
        <CommonIcon v-else name="play-circle" />
      </div>

      <figcaption>
        <CommonLabel class="block! text-center">{{ label }}</CommonLabel>
      </figcaption>
    </figure>

    <div
      v-if="!circle && entityType === DragAndDropBulkEntityType.Ticket"
      ref="inside-group"
      v-tooltip="$t('Go inside group')"
      class="flex h-12 w-full items-center justify-center rounded-b-lg border-t-0"
      :class="hoverClass"
    >
      <CommonIcon name="arrow-down-short" />
    </div>
  </div>
</template>
