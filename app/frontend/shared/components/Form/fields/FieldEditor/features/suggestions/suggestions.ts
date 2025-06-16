// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { PluginKey } from '@tiptap/pm/state'
import { VueRenderer } from '@tiptap/vue-3'
import { useDebounceFn } from '@vueuse/core'

import type { MentionType } from '#shared/components/Form/fields/FieldEditor/types.ts'
import {
  autoUpdatePosition,
  setFloatingPopover,
} from '#shared/components/Form/fields/FieldEditor/utils.ts'
import { getEditorComponents } from '#shared/components/Form/initializeFieldEditor.ts'

import type { Content, Editor } from '@tiptap/core'
import type { SuggestionOptions, SuggestionProps } from '@tiptap/suggestion'

interface MentionOptions<T> {
  activator: string
  type: MentionType
  allowSpaces?: boolean
  items(props: { query: string; editor: Editor }): T[] | Promise<T[]>
  // oxlint-disable-next-line no-explicit-any
  insert(props: Record<string, any>): Content | Promise<Content>
}

export default function buildMentionExtension<T>(
  options: MentionOptions<T>,
): Omit<SuggestionOptions, 'editor'> {
  return {
    char: options.activator,
    allowSpaces: options.allowSpaces,
    items: options.items,
    pluginKey: new PluginKey(options.type),
    command({ editor, range, props }) {
      // increase range.to by one when the next node is of type "text"
      // and starts with a space character
      const { nodeAfter } = editor.view.state.selection.$to
      const overrideSpace = nodeAfter?.text?.startsWith(' ')

      // activators start with a space, so we need to decrease the range
      range.from -= 1
      if (overrideSpace) {
        range.to += 1
      }

      const insert = (content: Content) => {
        editor.chain().focus().insertContentAt(range, content).run()
      }

      const content = options.insert(props)

      if (content instanceof Promise) {
        content.then((c) => insert(c))
      } else {
        insert(content)
      }
    },
    render() {
      let component: VueRenderer | null

      const renderFn = (loadingState: boolean) => {
        return useDebounceFn(function (props: SuggestionProps) {
          if (!component) {
            component = setFloatingPopover(getEditorComponents().suggestionList!, props.editor, {
              loading: loadingState,
              query: props.query,
              items: props.items,
              command: props.command,
              type: options.type,
            })
          } else {
            component?.updateProps({
              loading: loadingState,
              query: props.query,
              items: props.items,
              command: props.command,
              type: options.type,
            })
          }

          autoUpdatePosition(props.editor, component!.element as HTMLElement)
        }, 200)
      }

      return {
        onBeforeStart: renderFn(true),
        onStart: renderFn(false),
        onBeforeUpdate: renderFn(true),
        onUpdate: renderFn(false),

        onKeyDown(props) {
          if (props.event.key === 'Escape') {
            component?.destroy()

            return true
          }

          return component?.ref?.onKeyDown(props)
        },

        onExit() {
          component?.destroy()
          component = null
        },
      }
    },
  }
}
