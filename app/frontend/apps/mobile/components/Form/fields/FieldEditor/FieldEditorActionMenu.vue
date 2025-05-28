<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { findParentNodeClosestToPos } from '@tiptap/core'
import { useEventListener } from '@vueuse/core'
import { computed, ref } from 'vue'

import type { ActionMenuProps } from '#shared/components/Form/fields/FieldEditor/FieldEditorActionMenu/types.ts'
import type { EditorButton } from '#shared/components/Form/fields/FieldEditor/useEditorActions.ts'

import CommonSectionPopup from '#mobile/components/CommonSectionPopup/CommonSectionPopup.vue'
import type { PopupItemDescriptor } from '#mobile/components/CommonSectionPopup/types.ts'

defineEmits<{
  hide: []
  blur: []
  'click-action': [EditorButton, MouseEvent]
}>()

const props = withDefaults(defineProps<ActionMenuProps>(), {
  visible: true,
})

const showPopup = ref(false)

const handleClose = () => {
  showPopup.value = false
}

const messages = computed<PopupItemDescriptor[]>(() =>
  Array.isArray(props.actions)
    ? props.actions?.map((action) => ({
        type: 'button',
        label: action.label || action.name,
        buttonVariant: 'secondary',
        buttonPrefixIcon: action.icon,
        buttonAlign: 'start',
        onAction: () => {
          action.command?.(new MouseEvent('click'))
        },
      }))
    : [],
)

useEventListener('click', (event: MouseEvent) => {
  const { editor } = props

  if (!editor) return

  const { target } = event

  if (!(target as HTMLElement).closest('[data-type="editor"]')) return

  const nearestTableParent = findParentNodeClosestToPos(
    editor.state.selection.$anchor,
    (node) => node.type.name === props.typeName,
  )

  if (!nearestTableParent) {
    showPopup.value = false
  } else {
    const wrapperDomNode = editor.view.nodeDOM(nearestTableParent.pos) as
      | HTMLElement
      | null
      | undefined

    const tableDomNode = wrapperDomNode?.querySelector('table')

    if (tableDomNode) {
      showPopup.value = true
    }
  }
})

defineExpose({
  close: handleClose,
})
</script>

<template>
  <CommonSectionPopup
    v-model:state="showPopup"
    :messages="messages"
    no-refocus
    @close="handleClose"
  />
</template>
