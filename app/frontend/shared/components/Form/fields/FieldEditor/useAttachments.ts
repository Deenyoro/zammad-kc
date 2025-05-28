// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import log from '#shared/utils/log.ts'

import { getNodeByName } from '../../utils.ts'

import { convertInlineImages } from './utils.ts'

import type { Extensions } from '@tiptap/core'
import type { Editor } from '@tiptap/vue-3'

interface LoadImagesOptions {
  attachNonInlineFiles: boolean
}

export const useAttachments = (extensions: Extensions, formId: string) => {
  const hasImageExtension = extensions.some(
    (extension) => extension.name === 'image',
  )

  const inlineImagesInEditor = (editor: Editor, files: File[]) => {
    convertInlineImages(files, editor.view.dom).then(async (urls) => {
      if (editor?.isDestroyed) return
      editor?.commands.setImages(urls)
    })
  }

  const addFilesToAttachments = (files: File[]) => {
    const attachmentsContext = getNodeByName(formId, 'attachments')
      ?.context as unknown as
      | { uploadFiles?: (files: File[]) => void }
      | undefined
    if (attachmentsContext && !attachmentsContext.uploadFiles) {
      log.error(
        '[FieldEditorInput] Attachments field was found, but it doesn\'t provide "uploadFiles" method.',
      )
    } else {
      attachmentsContext?.uploadFiles?.(files)
    }
  }

  // there is also a gif, but desktop only inlines these two for now
  const imagesMimeType = ['image/png', 'image/jpeg']
  const loadFiles = (
    files: FileList | File[] | null | undefined,
    editor: Editor | undefined,
    options: LoadImagesOptions,
  ) => {
    if (!files) {
      return false
    }

    const inlineImages: File[] = []
    const otherFiles: File[] = []

    for (const file of files) {
      if (imagesMimeType.includes(file.type)) {
        inlineImages.push(file)
      } else {
        otherFiles.push(file)
      }
    }

    if (inlineImages.length && editor) {
      inlineImagesInEditor(editor, inlineImages)
    }

    if (options.attachNonInlineFiles && otherFiles.length) {
      addFilesToAttachments(otherFiles)
    }

    return Boolean(
      inlineImages.length ||
        (options.attachNonInlineFiles && otherFiles.length),
    )
  }

  return {
    hasImageExtension,
    loadFiles,
  }
}
