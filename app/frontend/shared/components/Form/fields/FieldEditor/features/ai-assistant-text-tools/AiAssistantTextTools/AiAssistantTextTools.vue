<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed, nextTick, onMounted } from 'vue'

import {
  useNotifications,
  NotificationTypes,
} from '#shared/components/CommonNotifications/index.ts'
import { getAiAssistantTextToolsClasses } from '#shared/components/Form/fields/FieldEditor/features/ai-assistant-text-tools/AiAssistantTextTools/initializeAiAssistantTextTools.ts'
import type { FieldEditorProps } from '#shared/components/Form/fields/FieldEditor/types.ts'
import type { FormFieldContext } from '#shared/components/Form/types/field.ts'

import type { Editor } from '@tiptap/vue-3'

const props = defineProps<{
  editor?: Editor
  formContext?: FormFieldContext<FieldEditorProps>
}>()

const emit = defineEmits<{
  close: []
  action: []
  'hide-action-bar': [boolean]
  'show-ai-text-loader': [boolean]
}>()

const smartEditorClasses = getAiAssistantTextToolsClasses()

const { notify } = useNotifications()

const hasSelection = computed(
  () =>
    props.editor?.state.selection.anchor !== props.editor?.state.selection.head,
)

onMounted(() => {
  if (hasSelection.value) return

  nextTick(() => {
    emit('close')

    notify({
      id: 'ai-assistant-text-tools-no-selection',
      type: NotificationTypes.Info,
      message: __('Please select some text first.'),
    })
  })
})

const actions = [
  {
    key: 'improve-writing',
    label: __('Improve writing'),
    disabled: !hasSelection.value,
    command: () => {
      emit('action')
      props.editor!.commands.improveWriting()
    },
  },
  {
    key: 'fix-spelling-grammar',
    label: __('Fix spelling and grammar'),
    disabled: !hasSelection.value,
    command: () => {
      emit('action')
      props.editor!.commands.fixSpellingAndGrammar()
    },
  },
  {
    key: 'expand',
    label: __('Expand'),
    disabled: !hasSelection.value,
    command: () => {
      emit('action')
      props.editor!.commands.expandText()
    },
  },
  {
    key: 'simplify',
    label: __('Simplify'),
    disabled: !hasSelection.value,
    command: () => {
      emit('action')
      props.editor!.commands.simplifyText()
    },
  },
]
</script>

<template>
  <div :class="smartEditorClasses.popover.base">
    <ul ref="list">
      <li
        v-for="action in actions"
        :key="action.key"
        :class="smartEditorClasses.popover.item"
      >
        <button
          :disabled="action.disabled"
          :class="smartEditorClasses.popover.button"
          class="disabled:pointer-events-none disabled:opacity-60"
          @click="action.command"
        >
          {{ $t(action.label) }}
        </button>
      </li>
    </ul>
  </div>
</template>

<style>
[data-theme='light'] [contenteditable='false'][name='body'] {
  color: #a0a3a6;

  * {
    color: currentColor;
  }
}

[contenteditable='false'][name='body'],
[data-theme='dark'] [contenteditable='false'][name='body'] {
  color: #999;

  * {
    color: currentColor;
  }
}

[data-theme='light'] [contenteditable='false'][name='body'] ::selection {
  color: #585856;
  background: transparent;
}

[contenteditable='false'][name='body'] ::selection,
[data-theme='dark'] [contenteditable='false'][name='body'] ::selection {
  color: #d1d1d1;
  background: transparent;
}
</style>
