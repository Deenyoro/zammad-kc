// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import type { PossibleSignature } from '#shared/components/Form/fields/FieldEditor/types.ts'
import testFlags from '#shared/utils/testFlags.ts'

import type { Editor } from '@tiptap/vue-3'
import type { ShallowRef } from 'vue'

export const useSignatureHandling = (
  editor: ShallowRef<Editor | undefined>,
) => {
  // insert signature before full article blockquote or at the end of the document
  const resolveSignaturePosition = (editor: Editor) => {
    let blockquotePosition: number | null = null
    editor.state.doc.descendants((node, pos) => {
      if (
        (node.type.name === 'paragraph' || node.type.name === 'blockquote') &&
        node.attrs['data-marker'] === 'signature-before'
      ) {
        blockquotePosition = pos
        return false
      }
    })
    if (blockquotePosition !== null) {
      return { position: 'before', from: blockquotePosition }
    }
    return { position: 'after', from: editor.state.doc.content.size || 0 }
  }

  const addSignature = (signature: PossibleSignature) => {
    if (!editor.value || editor.value.isDestroyed || !editor.value.isEditable)
      return
    const currentPosition = editor.value.state.selection.anchor
    const positionFromEnd =
      editor.value.state.doc.content.size - currentPosition
    // don't use "chain()", because we change positions a lot
    // and chain doesn't know about it
    editor.value.commands.removeSignature()
    const { position, from } = resolveSignaturePosition(editor.value)
    editor.value.commands.addSignature({ ...signature, position, from })
    const getNewPosition = (editor: Editor) => {
      if (signature.position != null) {
        return signature.position
      }
      if (currentPosition < from) {
        return currentPosition
      }
      if (from === 0 && currentPosition <= 1) {
        return 1
      }
      return editor.state.doc.content.size - positionFromEnd
    }
    // calculate new position from the end of the signature otherwise
    editor.value.commands.focus(getNewPosition(editor.value))
    requestAnimationFrame(() => {
      testFlags.set('editor.signatureAdd')
    })
  }

  const removeSignature = () => {
    if (!editor.value || editor.value.isDestroyed || !editor.value.isEditable)
      return
    const currentPosition = editor.value.state.selection.anchor
    editor.value.chain().removeSignature().focus(currentPosition).run()
    requestAnimationFrame(() => {
      testFlags.set('editor.removeSignature')
    })
  }

  return {
    addSignature,
    removeSignature,
  }
}
