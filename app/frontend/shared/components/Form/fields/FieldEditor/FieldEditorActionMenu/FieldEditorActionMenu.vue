<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script lang="ts" setup>
import { useTemplateRef } from 'vue'

import { getEditorActionMenu } from '#shared/components/Form/fields/FieldEditor/FieldEditorActionMenu/initializeActionMenu.ts'
import type { ActionMenuProps } from '#shared/components/Form/fields/FieldEditor/FieldEditorActionMenu/types.ts'
import type { EditorButton } from '#shared/components/Form/fields/FieldEditor/types.ts'

const component = getEditorActionMenu()

const props = defineProps<ActionMenuProps>()

const actionMenuInstance = useTemplateRef<{ close: () => void }>('action-menu')

defineEmits<{
  'click-action': [EditorButton, MouseEvent]
}>()

defineExpose({
  close: () => actionMenuInstance.value?.close(),
})
</script>

<template>
  <Component
    v-bind="props"
    :is="component"
    ref="action-menu"
    @click-action="
      (action: EditorButton, event: MouseEvent) =>
        $emit('click-action', action, event)
    "
  >
    <template #default="slotProps">
      <slot v-bind="slotProps" />
    </template>
  </Component>
</template>
