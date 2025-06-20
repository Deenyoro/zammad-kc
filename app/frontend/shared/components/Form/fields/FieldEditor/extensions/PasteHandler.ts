// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { Extension } from '@tiptap/core'
import { Plugin, PluginKey } from '@tiptap/pm/state'

import { htmlCleanup } from '#shared/utils/htmlCleanup.ts'

export const PasteHandlerPluginKey = new PluginKey('paste-handler')

export const PasteHandler = Extension.create({
  name: 'paste-handler',

  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: PasteHandlerPluginKey,
        props: {
          handlePaste: (view, event) => {
            const { clipboardData } = event
            if (!clipboardData) return false

            const content = clipboardData.getData('text/html')

            // If no HTML content, let ProseMirror handle plain text.
            if (!content) return false

            const cleanContent = htmlCleanup(content)

            // Use TipTap's editor API to insert the content
            this.editor.commands.insertContent(cleanContent)

            event.preventDefault()

            return true
          },
        },
      }),
    ]
  },
})
