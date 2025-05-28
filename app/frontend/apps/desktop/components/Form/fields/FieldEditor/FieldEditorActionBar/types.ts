// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import type { EditorButton } from '#shared/components/Form/fields/FieldEditor/useEditorActions.ts'

export interface ExtendedEditorButton extends EditorButton {
  key: string
  noCloseOnClick: boolean
}
