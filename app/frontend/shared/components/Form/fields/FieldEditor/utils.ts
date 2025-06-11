// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { DOMSerializer } from 'prosemirror-model'

import { convertFileList } from '#shared/utils/files.ts'

import type { Editor } from '@tiptap/core'

export const populateEditorNewLines = (htmlContent: string): string => {
  const body = document.createElement('div')
  body.innerHTML = htmlContent
  // prosemirror always adds a visible linebreak inside an empty paragraph,
  // but it doesn't return it inside a schema, so we need to add it manually
  body.querySelectorAll('p').forEach((p) => {
    p.removeAttribute('data-marker')
    if (
      p.childNodes.length === 0 ||
      p.lastChild?.nodeType !== Node.TEXT_NODE ||
      p.textContent?.endsWith('\n')
    ) {
      p.appendChild(document.createElement('br'))
    }
  })
  return body.innerHTML
}

export const convertInlineImages = (
  inlineImages: FileList | File[],
  editorElement: HTMLElement,
) => {
  return convertFileList(inlineImages, {
    compress: true,
    onCompress: () => {
      const editorWidth = editorElement.clientWidth
      const maxWidth = editorWidth > 1000 ? editorWidth : 1000
      return {
        x: maxWidth,
        scale: 2,
        type: 'image/jpeg',
      }
    },
  })
}

export const getSelection = (editor: Editor) => editor.state.selection

export const getHTMLFromSelection = (
  editor: Editor,
  selection?: Editor['state']['selection'],
) => {
  const sel = selection ?? editor!.state.selection
  const slice = sel.content()
  const serializer = DOMSerializer.fromSchema(editor!.schema)
  const fragment = serializer.serializeFragment(slice.content)
  const div = document.createElement('div')
  div.appendChild(fragment)

  return div.innerHTML
}

export const updateSelectedContent = (editor: Editor, content: string) => {
  editor!.commands.deleteSelection()

  // Remove visual newlines from the model which should not play any role.
  return editor!.commands.insertContent(content.replace(/\s*\n\s*/g, ''))
}
