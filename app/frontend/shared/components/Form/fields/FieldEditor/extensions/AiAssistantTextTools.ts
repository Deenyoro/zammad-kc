// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { Extension } from '@tiptap/core'
import { effectScope, ref, type Ref, watch } from 'vue'

import {
  NotificationTypes,
  useNotifications,
} from '#shared/components/CommonNotifications/index.ts'
import { useAiAssistanceTextToolsListQuery } from '#shared/components/Form/fields/FieldEditor/graphql/queries/aiAssistanceTextTools/aiAssistanceTextToolsList.api.ts'
import type { FieldEditorProps } from '#shared/components/Form/fields/FieldEditor/types.ts'
import {
  getHTMLFromSelection,
  updateSelectedContent,
} from '#shared/components/Form/fields/FieldEditor/utils.ts'
import type { FormFieldContext } from '#shared/components/Form/types/field.ts'
import { getNodeByName } from '#shared/components/Form/utils.ts'
import { useAiAssistanceTextToolsRunMutation } from '#shared/graphql/mutations/aiAssistanceTextToolsRun.api.ts'
import { convertToGraphQLId, ensureGraphqlId } from '#shared/graphql/utils.ts'
import { MutationHandler, QueryHandler } from '#shared/server/apollo/handler/index.ts'
import { useAiAssistantTextToolsStore } from '#shared/stores/aiAssistantTextTools.ts'
import { useApplicationStore } from '#shared/stores/application.ts'
import { GraphQLErrorTypes } from '#shared/types/error.ts'

import type { FormKitNode } from '@formkit/core'

export const PLUGIN_NAME = 'aiAssistantTextTools'

export default (context: Ref<FormFieldContext<FieldEditorProps>>) => {
  const { formId, ticketId, meta: editorMeta } = context.value
  const meta = editorMeta?.[PLUGIN_NAME] || {}
  let scope = effectScope()

  return Extension.create({
    name: PLUGIN_NAME,
    addStorage() {
      return {
        showAiTextLoader: false,
      }
    },
    onBeforeCreate({ editor }) {
      const { config } = useApplicationStore()

      watch(
        () => config.ai_assistance_text_tools,
        (newValue) => {
          if (!newValue) {
            if (scope.active) scope.stop()
            return
          }

          if (!scope.active) {
            scope = effectScope()
          }

          scope.run(() => {
            const textToolsStore = useAiAssistantTextToolsStore()

            const groupNode = getNodeByName(formId, meta.groupNodeName!) as FormKitNode<number>

            const groupId = ref<number>(groupNode?.value)

            groupNode?.on('commit', ({ payload }) => {
              groupId.value = payload
            })

            const queryHandler = new QueryHandler(
              useAiAssistanceTextToolsListQuery(() => ({
                groupId: groupId.value ? convertToGraphQLId('Group', groupId.value) : undefined,
                ticketId: ticketId ? convertToGraphQLId('Ticket', ticketId) : undefined,
              })),
            )

            queryHandler.watchOnResult(({ aiAssistanceTextToolsList }) => {
              if (!editor) return

              editor.emit('toggle-visibility', {
                name: PLUGIN_NAME,
                active: !!aiAssistanceTextToolsList.length,
              })
            })

            watch(
              () => groupId.value,
              (newGroupId, oldGroupId) => {
                // If the groupId changes, we deactivate the old one
                if (oldGroupId !== newGroupId) textToolsStore.deactivate(oldGroupId)

                textToolsStore.activate(newGroupId, queryHandler)
              },
              { immediate: true },
            )

            editor.on('destroy', () => textToolsStore.deactivate(groupId.value))
          })
        },
        { immediate: true },
      )
    },
    addCommands() {
      return {
        modifySelectedText:
          (textToolId) =>
          ({ editor }) => {
            const showActionBarAndHideAiTextLoader = () => {
              editor.setEditable(true)
              editor.storage.showAiTextLoader = false
            }

            const hideActionBarAndShowAiTextLoader = () => {
              editor.setEditable(false)
              editor.storage.showAiTextLoader = true
            }

            let mutationGotCancelled = false

            const useAbortableMutation = () => {
              const abortController = new AbortController()

              const textToolsMutation = new MutationHandler(
                useAiAssistanceTextToolsRunMutation({
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

            const sendTextToolsMutation = async (textToolId: ID, input: string) => {
              const { ticketId } = context.value
              let { customerId, groupId, organizationId } = context.value

              if (!customerId && meta.customerNodeName) {
                const node = getNodeByName(formId, meta.customerNodeName)
                customerId = node?.value as string
              }

              if (!organizationId && meta.organizationNodeName) {
                const node = getNodeByName(formId, meta.organizationNodeName)
                organizationId = node?.value as string
              }

              if (!groupId && meta.groupNodeName) {
                const node = getNodeByName(formId, meta.groupNodeName)
                groupId = node?.value as string
              }

              const response = await aiAssistanceTextToolsController.textToolsMutation.send({
                input,
                textToolId: textToolId,
                templateRenderContext: {
                  customerId: customerId ? ensureGraphqlId('User', customerId) : undefined,
                  groupId: groupId ? ensureGraphqlId('Group', groupId) : undefined,
                  organizationId: organizationId
                    ? ensureGraphqlId('Organization', organizationId)
                    : undefined,
                  ticketId: ticketId ? ensureGraphqlId('Ticket', ticketId) : undefined,
                },
              })

              return response?.aiAssistanceTextToolsRun?.output
            }

            const modifySelectedText = async (textToolId: ID) => {
              const lastSelection = editor.state.selection

              const input = getHTMLFromSelection(editor, lastSelection)

              hideActionBarAndShowAiTextLoader()

              const { notify } = useNotifications()

              editor.on('cancel-ai-assistant-text-tools-updates', () => {
                mutationGotCancelled = true
                aiAssistanceTextToolsController.abort()
                aiAssistanceTextToolsController = useAbortableMutation()

                mutationGotCancelled = false
              })

              editor.on('update', () => {
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

              return sendTextToolsMutation(textToolId, input)
                .then((output) => {
                  if (!output) return

                  // Make sure the right selection is always set
                  editor.chain().focus().setTextSelection(lastSelection).run()

                  updateSelectedContent(editor, output)
                })
                .catch(() => {
                  editor?.chain().focus().setTextSelection(lastSelection).run()
                })
                .finally(showActionBarAndHideAiTextLoader)
            }
            modifySelectedText(textToolId).then(() => {
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
    onDestroy() {
      scope.stop()
    },
  })
}
