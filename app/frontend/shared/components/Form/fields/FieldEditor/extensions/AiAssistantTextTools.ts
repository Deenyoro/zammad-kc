// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { Extension } from '@tiptap/core'

import {
  NotificationTypes,
  useNotifications,
} from '#shared/components/CommonNotifications/index.ts'
import {
  getHTMLFromSelection,
  updateSelectedContent,
} from '#shared/components/Form/fields/FieldEditor/utils.ts'
import { useAiAssistanceTextToolsMutation } from '#shared/graphql/mutations/aiAssistanceTextTools.api.ts'
import { EnumAiTextToolService } from '#shared/graphql/types.ts'
import { MutationHandler } from '#shared/server/apollo/handler/index.ts'
import { GraphQLErrorTypes } from '#shared/types/error.ts'

import type { Editor } from '@tiptap/vue-3'
import type { ShallowRef } from 'vue'

export default (editor: ShallowRef<Editor>) => {
  const showActionBarAndHideAiTextLoader = () => {
    editor.value.setEditable(true)
    editor.value.storage.showAiTextLoader = false
  }

  const hideActionBarAndShowAiTextLoader = () => {
    editor.value.setEditable(false)
    editor.value.storage.showAiTextLoader = true
  }

  let mutationGotCancelled = false

  const useAbortableMutation = () => {
    const abortController = new AbortController()

    const textToolsMutation = new MutationHandler(
      useAiAssistanceTextToolsMutation({
        context: { fetchOptions: { signal: abortController.signal } },
      }),
      {
        errorCallback: (error) => {
          return !(mutationGotCancelled && error.type === GraphQLErrorTypes.NetworkError)
        },
      },
    )
    return {
      textToolsMutation,
      isLoading: textToolsMutation.loading(),
      abortController,
      abort: () => abortController.abort(),
    }
  }

  let aiAssistanceTextToolsController = useAbortableMutation()

  const sendTextToolsMutation = async (textToolService: EnumAiTextToolService, input: string) => {
    const response = await aiAssistanceTextToolsController.textToolsMutation.send({
      input,
      serviceType: textToolService,
    })
    return response?.aiAssistanceTextTools?.output
  }

  const modifySelectedText = async (textToolService: EnumAiTextToolService) => {
    const lastSelection = editor.value.state.selection

    const input = getHTMLFromSelection(editor.value, lastSelection)

    hideActionBarAndShowAiTextLoader()

    const { notify } = useNotifications()

    editor.value.on('cancel-ai-assistant-text-tools-updates', () => {
      mutationGotCancelled = true
      aiAssistanceTextToolsController.abort()
      aiAssistanceTextToolsController = useAbortableMutation()

      mutationGotCancelled = false
    })

    editor.value.on('update', () => {
      if (aiAssistanceTextToolsController.isLoading.value) {
        notify({
          id: 'ai-assistant-text-tools-aborted',
          type: NotificationTypes.Info,
          message: __(
            'The text was modified. Your request has been aborted to prevent overwriting.',
          ),
        })
        aiAssistanceTextToolsController.abort()
        aiAssistanceTextToolsController = useAbortableMutation()
      }
    })

    return sendTextToolsMutation(textToolService, input)
      .then((output) => {
        if (!output) return

        // Make sure the right selection is always set
        editor.value.chain().focus().setTextSelection(lastSelection).run()

        updateSelectedContent(editor.value, output)
      })
      .catch(() => {
        editor?.value.chain().focus().setTextSelection(lastSelection).run()
      })
      .finally(showActionBarAndHideAiTextLoader)
  }

  return Extension.create({
    name: 'AiAssistantTextTools',
    addStorage() {
      return {
        showAiTextLoader: false,
      }
    },
    addCommands() {
      return {
        improveWriting:
          () =>
          ({ editor }) => {
            modifySelectedText(EnumAiTextToolService.ImproveWriting).then(() => {
              editor.chain().focus().run()
            })
            return true
          },
        fixSpellingAndGrammar:
          () =>
          ({ editor }) => {
            modifySelectedText(EnumAiTextToolService.SpellingAndGrammar).then(() => {
              editor.chain().focus().run()
            })
            return true
          },
        expandText:
          () =>
          ({ editor }) => {
            modifySelectedText(EnumAiTextToolService.Expand).then(() => {
              editor.chain().focus().run()
            })
            return true
          },
        simplifyText:
          () =>
          ({ editor }) => {
            modifySelectedText(EnumAiTextToolService.Simplify).then(() => {
              editor.chain().focus().run()
            })
            return true
          },
      }
    },
    addOptions() {
      return {
        permission: 'ticket.agent',
      }
    },
  })
}
