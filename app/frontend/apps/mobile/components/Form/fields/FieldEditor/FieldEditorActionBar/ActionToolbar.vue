<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { onKeyDown, useEventListener, whenever } from '@vueuse/core'
import { useTemplateRef } from 'vue'
import { nextTick, type Ref, ref, toRef } from 'vue'

import type { EditorButton } from '#shared/components/Form/fields/FieldEditor/types.ts'
import { useTraverseOptions } from '#shared/composables/useTraverseOptions.ts'
import stopEvent from '#shared/utils/events.ts'

import type { Editor } from '@tiptap/core'

interface Props {
  actions: EditorButton[]
  editor?: Editor
  visible?: boolean
  isActive?: (type: string, attributes?: Record<string, unknown>) => boolean
  noGradient?: boolean
}

const actionBar = useTemplateRef('action-bar')

const props = withDefaults(defineProps<Props>(), {
  visible: true,
})

const editor = toRef(props, 'editor')

const emit = defineEmits<{
  hide: []
  blur: []
  'click-action': [EditorButton, MouseEvent]
}>()

const opacityGradientEnd = ref('0')
const opacityGradientStart = ref('0')

const restoreScroll = () => {
  const menuBar = actionBar.value as HTMLElement
  // restore scroll position, if needed
  menuBar.scroll(0, 0)
}

const hideAfterLeaving = () => {
  restoreScroll()
  emit('hide')
}

const recalculateOpacity = () => {
  const target = actionBar.value
  if (!target) {
    return
  }
  const scrollMin = 40
  const bottomMax = target.scrollWidth - target.clientWidth
  const bottomMin = bottomMax - scrollMin
  const { scrollLeft } = target
  opacityGradientStart.value = Math.min(1, scrollLeft / scrollMin).toFixed(2)
  const opacityPart = (scrollLeft - bottomMin) / scrollMin
  opacityGradientEnd.value = Math.min(1, 1 - opacityPart).toFixed(2)
}

useTraverseOptions(actionBar, { direction: 'horizontal', ignoreTabindex: true })

onKeyDown(
  'Escape',
  (e) => {
    stopEvent(e)
    emit('blur')
  },
  { target: actionBar as Ref<EventTarget> },
)

useEventListener('click', (e) => {
  if (!actionBar.value) return

  const target = e.target as HTMLElement

  if (!actionBar.value.contains(target) && !editor.value?.isFocused) {
    restoreScroll()
    emit('hide')
  }
})

whenever(
  () => props.visible,
  () => nextTick(recalculateOpacity),
)
</script>

<template>
  <div class="relative">
    <!-- eslint-disable vuejs-accessibility/no-static-element-interactions -->
    <div
      ref="action-bar"
      data-test-id="action-bar"
      class="Menubar relative flex max-w-full items-center gap-1 overflow-x-auto overflow-y-hidden p-2"
      role="toolbar"
      tabindex="0"
      @keydown.tab="hideAfterLeaving"
      @scroll.passive="recalculateOpacity"
    >
      <template v-for="(action, idx) in actions" :key="action.name">
        <button
          :title="$t(action.label || action.name)"
          type="button"
          class="flex items-center gap-1 rounded bg-black p-2 lg:hover:bg-gray-300"
          :class="[
            action.class,
            {
              'bg-gray-300': isActive?.(action.name, action.attributes),
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
          @click="
            (event) => {
              action.command?.(event)
              $emit('click-action', action, event)
            }
          "
        >
          <CommonIcon :name="action.icon" size="small" decorative />
          <CommonIcon v-if="action.subMenu" name="caret" size="xs" decorative />
        </button>
        <div v-if="action.showDivider && idx < actions.length - 1">
          <hr :class="action.dividerClass" class="h-6 w-px border-0 bg-black" />
        </div>
      </template>
    </div>
    <template v-if="!props.noGradient">
      <div class="ShadowGradient LeftGradient" :style="{ opacity: opacityGradientStart }" />
      <div class="ShadowGradient RightGradient" :style="{ opacity: opacityGradientEnd }" />
    </template>
  </div>
</template>

<style scoped>
.Menubar {
  -ms-overflow-style: none; /* Internet Explorer 10+ */
  scrollbar-width: none; /* Firefox */

  &::-webkit-scrollbar {
    display: none; /* Safari and Chrome */
  }
}

.ShadowGradient {
  position: absolute;
  height: 100%;
  width: 2rem;
}

.ShadowGradient::before {
  border-radius: 0 0 0.5rem;
  content: '';
  position: absolute;
  top: calc(0px - 30px - 1.5rem);
  height: calc(30px + 1.5rem);
  pointer-events: none;
}

.LeftGradient::before {
  border-radius: 0 0 0 0.5rem;
  left: -0.5rem;
  right: 0;
  background: linear-gradient(270deg, rgba(255, 255, 255, 0), #282829);
}

.RightGradient {
  right: 0;
}

.RightGradient::before {
  right: 0;
  left: 0;
  background: linear-gradient(90deg, rgba(255, 255, 255, 0), #282829);
}

.color-indicator {
  --color-indicator-background: transparent;

  position: relative;

  &::before {
    content: '';
    border: solid 1px var(--color-gray-400);
    background: var(--color-indicator-background) !important;
    position: absolute;
    bottom: 0.6rem;
    left: 50%;
    height: 0.25rem;
    width: 0.25rem;
    transform: translateX(-50%);
    border-radius: 2px;
    box-sizing: content-box;
  }
}
</style>
