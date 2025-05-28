<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { DOMSerializer } from 'prosemirror-model'
import { computed, nextTick, onMounted, watch } from 'vue'

import {
  useNotifications,
  NotificationTypes,
} from '#shared/components/CommonNotifications/index.ts'
import { getAiAssistantTextToolsClasses } from '#shared/components/Form/fields/FieldEditor/AiAssistantTextTools/initializeAiAssistantTextTools.ts'
import type { FieldEditorProps } from '#shared/components/Form/fields/FieldEditor/types.ts'
import type { FormFieldContext } from '#shared/components/Form/types/field.ts'
import { useAiAssistanceTextToolsMutation } from '#shared/graphql/mutations/aiAssistanceTextTools.api.ts'
import { EnumAiTextToolService } from '#shared/graphql/types.ts'
import { MutationHandler } from '#shared/server/apollo/handler/index.ts'

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

const useAbortableMutation = () => {
  const abortController = new AbortController()

  const textToolsMutation = new MutationHandler(
    useAiAssistanceTextToolsMutation({
      context: { fetchOptions: { signal: abortController.signal } },
    }),
  )
  return {
    textToolsMutation,
    isLoading: textToolsMutation.loading(),
    abortController,
    abort: () => abortController.abort(),
  }
}

let aiAssistanceTextToolsController = useAbortableMutation()

watch(
  () => props.formContext?.value,
  () => {
    if (aiAssistanceTextToolsController.isLoading.value) {
      notify({
        id: 'ai-assistant-text-tools-aborted',
        type: NotificationTypes.Info,
        message: __(
          'The text was modified. Your request has been aborted to prevent overwriting.',
        ),
      })
      aiAssistanceTextToolsController.abort()
      aiAssistanceTextToolsController = useAbortableMutation()
    }
  },
)

props.editor?.on('cancel-ai-assistant-text-tools-updates', () => {
  aiAssistanceTextToolsController.abort()
  aiAssistanceTextToolsController = useAbortableMutation()
})

const sendTextToolsMutation = async (
  textToolService: EnumAiTextToolService,
  input: string,
) => {
  const response = await aiAssistanceTextToolsController.textToolsMutation.send(
    {
      input,
      serviceType: textToolService,
    },
  )
  return response?.aiAssistanceTextTools?.output
}

// :TODO - Custom command maybe?
const getSelection = () => props.editor!.state.selection

// :TODO - Custom command maybe?
const getHTMLFromSelection = (selection: Editor['state']['selection']) => {
  const slice = selection.content()
  const serializer = DOMSerializer.fromSchema(props.editor!.schema)
  const fragment = serializer.serializeFragment(slice.content)
  const div = document.createElement('div')
  div.appendChild(fragment)

  return div.innerHTML
}

const updateSelectedContent = (content: string) => {
  props.editor!.commands.deleteSelection()

  // Remove visual newlines from the model which should not play any role.
  props.editor!.commands.insertContent(content.replace(/\s*\n\s*/g, ''))
}

const hideActionBarAndShowAiTextLoader = () => {
  emit('action')
  props.editor!.setEditable(false)
  emit('hide-action-bar', true)
  emit('show-ai-text-loader', true)
}

const showActionBarAndHideAiTextLoader = () => {
  emit('hide-action-bar', false)
  emit('show-ai-text-loader', false)
  props.editor!.setEditable(true)
}

const modifySelectedText = async (textToolService: EnumAiTextToolService) => {
  hideActionBarAndShowAiTextLoader()

  const lastSelection = getSelection()

  const input = getHTMLFromSelection(lastSelection)

  return sendTextToolsMutation(textToolService, input)
    .then((output) => {
      if (!output) return

      // Make sure the right selection is always set
      props.editor?.chain().focus().setTextSelection(lastSelection).run()

      updateSelectedContent(output)
    })
    .catch(() => {
      // Handle abort errors gracefully:
      // Currently, aborting a request triggers both a warning and an error toast,
      // as both are instances of ApolloError. Disabling toast messages entirely
      // would suppress all mutation-related errors, not just abort errors.
      // TODO: Investigate a way to suppress only abort-related error messages
      // while preserving other mutation error notifications.
      props.editor?.chain().focus().setTextSelection(lastSelection).run()
    })
    .finally(showActionBarAndHideAiTextLoader)
}

const actions = computed(() => [
  {
    key: 'improve-writing',
    label: __('Improve writing'),
    disabled: !hasSelection.value,
    onClick: () => modifySelectedText(EnumAiTextToolService.ImproveWriting),
  },
  {
    key: 'fix-spelling-grammar',
    label: __('Fix spelling and grammar'),
    disabled: !hasSelection.value,
    onClick: () => modifySelectedText(EnumAiTextToolService.SpellingAndGrammar),
  },
  {
    key: 'expand',
    label: __('Expand'),
    disabled: !hasSelection.value,
    onClick: () => modifySelectedText(EnumAiTextToolService.Expand),
  },
  {
    key: 'simplify',
    label: __('Simplify'),
    disabled: !hasSelection.value,
    onClick: () => modifySelectedText(EnumAiTextToolService.Simplify),
  },
])
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
          @click="action.onClick"
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
