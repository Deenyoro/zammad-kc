// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { autoUpdate, computePosition, flip, shift } from '@floating-ui/dom'
import { posToDOMRect, VueRenderer } from '@tiptap/vue-3'
import { DOMSerializer } from 'prosemirror-model'

import { convertFileList } from '#shared/utils/files.ts'

import type { Editor } from '@tiptap/core'
import type { Component } from 'vue'

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

/*
 * Selection specific utils
 */
export const getSelection = (editor: Editor) => editor.state.selection

export const getHTMLFromSelection = (editor: Editor, selection?: Editor['state']['selection']) => {
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

/*
 * Floating-ui
 */
export const updatePosition = (editor: Editor, element: HTMLElement) => {
  const virtualElement = {
    getBoundingClientRect: () =>
      posToDOMRect(editor.view, editor.state.selection.from, editor.state.selection.to),
  }

  computePosition(virtualElement, element, {
    placement: 'bottom-start',
    strategy: 'fixed',
    middleware: [shift(), flip()],
  }).then(({ x, y, strategy }) => {
    element.style.position = strategy
    element.style.left = `${x}px`
    element.style.top = `${y}px`
  })
}

export const getActiveNodeOrMark = (editor: Editor) => {
  const { node: domNode } = editor.view.domAtPos(editor.state.selection.from)

  return domNode.nodeType === Node.TEXT_NODE ? domNode.parentElement : (domNode as HTMLElement)
}

export const setAutoUpdate = (editor: Editor, element: HTMLElement) => {
  const anchorNode = getActiveNodeOrMark(editor)

  if (!anchorNode) {
    console.warn('FieldEditor: Could not find valid anchor node for autoUpdate.')
    return
  }

  return autoUpdate(anchorNode, element, () => updatePosition(editor, element))
}

export const autoUpdatePosition = (editor: Editor, element: HTMLElement) => {
  updatePosition(editor, element)
  setAutoUpdate(editor, element)
}

const createHandleCloseOnClick = (editor: Editor) => {
  const handleCloseOnClick = (event: MouseEvent) => {
    if ((event.target as HTMLElement).closest('[data-id="floating-popover"]')) return
    // Editor handles click itself
    if ((event.target as HTMLElement).closest('[data-type="editor"]')) return

    document.removeEventListener('click', handleCloseOnClick)
    editor.commands.closeLinkForm()
  }

  // We must do so to keep the same handler reference
  return handleCloseOnClick
}

export const setFloatingPopover = (cmp: Component, editor: Editor, props = {}) => {
  const virtualComponent = new VueRenderer(cmp, {
    props: {
      'data-id': 'floating-popover',
      editor,
      ...props,
    },
    editor,
  })

  if (!virtualComponent.element) {
    if (import.meta.env.DEV)
      console.warn('editor: Floating popover could`t get imported. Did you async load it?')
    return null
  }
  ;(virtualComponent.element as HTMLElement).style.position = 'absolute'

  document.body.appendChild(virtualComponent.element)

  autoUpdatePosition(editor, virtualComponent.element as HTMLElement)

  const clickHandler = createHandleCloseOnClick(editor)

  document.addEventListener('click', clickHandler)

  return virtualComponent
}
