<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { useIntersectionObserver } from '@vueuse/core'
import { useTemplateRef } from 'vue'

import type { EditorButton } from '#shared/components/Form/fields/FieldEditor/types.ts'

import type { Editor } from '@tiptap/core'

interface Props {
  action: EditorButton
  actionBar: HTMLDivElement | null
  editor?: Editor
  isActive?: (type: string, attributes?: Record<string, unknown>) => boolean
}

const props = defineProps<Props>()

const emit = defineEmits<{
  click: [MouseEvent]
  visible: [boolean]
}>()

const button = useTemplateRef('button')

const { pause: pauseIntersectionObserver, resume: resumeIntersectionObserver } =
  useIntersectionObserver(
    button,
    ([{ isIntersecting, target }]) => {
      if (isIntersecting && !props.action.disabled)
        (target as HTMLButtonElement).disabled = false
      else (target as HTMLButtonElement).disabled = true
      emit('visible', isIntersecting ?? false)
    },
    {
      root: props.actionBar,
      threshold: 0.1,
    },
  )

defineExpose({
  pauseIntersectionObserver,
  resumeIntersectionObserver,
})
</script>

<template>
  <button
    ref="button"
    v-tooltip="$t(action.label || action.name)"
    type="button"
    class="focus-visible-app-default transition-color flex items-center gap-1 rounded-lg p-1.5 hover:bg-blue-600 hover:text-black dark:hover:bg-blue-900 dark:hover:text-white"
    :class="[
      action.class,
      {
        'bg-blue-800! text-white': isActive?.(action.name, action.attributes),
        'color-indicator': action.name === 'textColor',
      },
    ]"
    :disabled="action.disabled"
    :style="{
      '--color-indicator-background': editor?.getAttributes('textStyle')?.color
        ? editor.getAttributes('textStyle').color
        : '#ffffff',
    }"
    :aria-label="$t(action.label || action.name)"
    :aria-pressed="isActive?.(action.name, action.attributes)"
    tabindex="-1"
    @click="$emit('click', $event)"
  >
    <CommonIcon :name="action.icon" size="tiny" decorative />
    <CommonIcon
      v-if="action.subMenu"
      name="chevron-down"
      :fixed-size="{ width: 10, height: 10 }"
      decorative
    />
  </button>
</template>

<style scoped>
.color-indicator {
  --color-indicator-background: transparent;

  position: relative;

  &::before {
    content: '';
    border: solid 1px var(--color-blue-50);
    background: var(--color-indicator-background) !important;
    position: absolute;
    bottom: 0.4rem;
    left: 50%;
    height: 0.25rem;
    width: 0.25rem;
    transform: translateX(-0.1rem);
    border-radius: 2px;
    box-sizing: content-box;
  }

  [data-theme='dark'] & {
    &::before {
      border-color: var(--color-gray-800);
    }
  }
}
</style>
