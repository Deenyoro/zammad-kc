// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { defineAsyncComponent } from 'vue'

import { initializeEditorActionMenu } from '#shared/components/Form/fields/FieldEditor/FieldEditorActionMenu/initializeActionMenu.ts'
import { initializeEditorActionBarComponent } from '#shared/components/Form/initializeEditorComponents.ts'

export default () => {
  initializeEditorActionBarComponent(
    defineAsyncComponent(
      () => import('#mobile/components/Form/fields/FieldEditor/FieldEditorActionBar.vue'),
    ),
  )
  initializeEditorActionMenu(
    defineAsyncComponent(
      () => import('#mobile/components/Form/fields/FieldEditor/FieldEditorActionMenu.vue'),
    ),
  )
}
