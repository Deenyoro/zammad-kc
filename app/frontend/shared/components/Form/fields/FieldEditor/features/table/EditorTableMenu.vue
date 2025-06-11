<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed, toRef, useTemplateRef } from 'vue'

import useEditorActionHelper from '#shared/components/Form/fields/FieldEditor/composables/useEditorActionHelper.ts'
import FieldEditorActionMenu from '#shared/components/Form/fields/FieldEditor/FieldEditorActionMenu/FieldEditorActionMenu.vue'
import type {
  EditorButton,
  EditorContentType,
} from '#shared/components/Form/fields/FieldEditor/types.ts'
import { i18n } from '#shared/i18n.ts'
import getUuid from '#shared/utils/getUuid.ts'

import type { Editor } from '@tiptap/vue-3'

const props = defineProps<{
  editor?: Editor
  contentType: EditorContentType
  formId: string
}>()

const editor = toRef(props, 'editor')

const { focused, canExecute } = useEditorActionHelper(editor)

const actionMenuInstance = useTemplateRef('action-menu')

const getActionsList = (): EditorButton[] => {
  if (!editor.value) return []

  return [
    {
      id: getUuid(),
      name: 'insertRowAbove',
      contentType: ['text/html'],
      label: i18n.t('Insert row above'),
      icon: 'insert-row-before',
      command: focused((c) => c.addRowBefore()),
      disabled: !canExecute('addRowBefore'),
    },
    {
      id: getUuid(),
      name: 'insertRowBelow',
      contentType: ['text/html'],
      label: i18n.t('Insert row below'),
      icon: 'insert-row-after',
      command: focused((c) => c.addRowAfter()),
      disabled: !canExecute('addRowAfter'),
    },
    {
      id: getUuid(),
      name: 'deleteRow',
      contentType: ['text/html'],
      label: i18n.t('Delete row'),
      icon: 'delete-row',
      command: focused((c) => c.deleteRow()),
      disabled: !canExecute('deleteRow'),
      showDivider: true,
    },
    {
      id: getUuid(),
      name: 'insertColumnBefore',
      contentType: ['text/html'],
      label: i18n.t('Insert column before'),
      icon: 'insert-column-before',
      command: focused((c) => c.addColumnBefore()),
      disabled: !canExecute('addColumnBefore'),
    },
    {
      id: getUuid(),
      name: 'insertColumnAfter',
      contentType: ['text/html'],
      label: i18n.t('Insert column after'),
      icon: 'insert-column-after',
      command: focused((c) => c.addColumnAfter()),
      disabled: !canExecute('addColumnAfter'),
    },
    {
      id: getUuid(),
      name: 'deleteColumn',
      contentType: ['text/html'],
      label: i18n.t('Delete column'),
      icon: 'delete-column',
      command: focused((c) => c.deleteColumn()),
      disabled: !canExecute('deleteColumn'),
      showDivider: true,
    },
    {
      id: getUuid(),
      name: 'splitCells',
      contentType: ['text/html'],
      label: i18n.t('Split cells'),
      icon: 'split-cells',
      command: focused((c) => c.splitCell()),
      disabled: !canExecute('splitCell'),
    },
    {
      id: getUuid(),
      name: 'mergeCells',
      contentType: ['text/html'],
      label: i18n.t('Merge cells'),
      icon: 'merge-cells',
      command: focused((c) => c.mergeCells()),
      disabled: !canExecute('mergeCells'),
      showDivider: true,
    },
    {
      id: getUuid(),
      name: 'toggleHeaderRow',
      contentType: ['text/html'],
      label: i18n.t('Toggle header row'),
      icon: 'toggle-header-row',
      command: focused((c) => c.toggleHeaderRow()),
      disabled: !canExecute('toggleHeaderRow'),
    },
    {
      id: getUuid(),
      name: 'toggleHeaderColumn',
      contentType: ['text/html'],
      label: i18n.t('Toggle header column'),
      icon: 'toggle-header-column',
      command: focused((c) => c.toggleHeaderColumn()),
      disabled: !canExecute('toggleHeaderColumn'),
    },
    {
      id: getUuid(),
      name: 'toggleHeaderCell',
      contentType: ['text/html'],
      label: i18n.t('Toggle header cell'),
      icon: 'toggle-header-cell',
      command: focused((c) => c.toggleHeaderCell()),
      disabled: !canExecute('toggleHeaderCell'),
      showDivider: true,
    },
    {
      id: getUuid(),
      name: 'deleteTable',
      contentType: ['text/html'],
      label: i18n.t('Delete table'),
      icon: 'delete-table',
      command: focused((c) => {
        actionMenuInstance.value?.close()
        return c.deleteTable()
      }),
      disabled: !canExecute('deleteTable'),
    },
  ]
}

const actions = computed(() =>
  getActionsList().filter((action) => {
    return action.contentType.includes(props.contentType)
  }),
)
</script>

<template>
  <FieldEditorActionMenu
    ref="action-menu"
    type-name="table"
    :content-type="contentType"
    :editor="editor"
    :actions="actions"
  />
</template>
