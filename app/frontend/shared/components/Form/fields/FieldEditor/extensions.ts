// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import Blockquote from '@tiptap/extension-blockquote'
import CharacterCount from '@tiptap/extension-character-count'
import CodeBlockLowlight from '@tiptap/extension-code-block-lowlight'
import Color from '@tiptap/extension-color'
import Paragraph from '@tiptap/extension-paragraph'
import { TableKit } from '@tiptap/extension-table'
import { TextStyle } from '@tiptap/extension-text-style'
import StarterKit from '@tiptap/starter-kit'
import { common, createLowlight } from 'lowlight'

import AiAssistantTextTools from '#shared/components/Form/fields/FieldEditor/extensions/AiAssistantTextTools.ts'
import HardBreakPlain from '#shared/components/Form/fields/FieldEditor/extensions/HardBreakPlain.ts'
import Image from '#shared/components/Form/fields/FieldEditor/extensions/Image.ts'
import { IndentExtension } from '#shared/components/Form/fields/FieldEditor/extensions/Indent.ts'
import KnowledgeBaseSuggestion from '#shared/components/Form/fields/FieldEditor/extensions/KnowledgeBaseSuggestion.ts'
import Link from '#shared/components/Form/fields/FieldEditor/extensions/Link.ts'
import Signature from '#shared/components/Form/fields/FieldEditor/extensions/Signature.ts'
import {
  MarginLeft,
  MarginRight,
} from '#shared/components/Form/fields/FieldEditor/extensions/Styles.ts'
import TextDirection, {
  type Direction,
} from '#shared/components/Form/fields/FieldEditor/extensions/TextDirection.ts'
import TextModuleSuggestion from '#shared/components/Form/fields/FieldEditor/extensions/TextModuleSuggestion.ts'
import UserMention, {
  UserLink,
} from '#shared/components/Form/fields/FieldEditor/extensions/UserMention.ts'
import type { FieldEditorProps } from '#shared/components/Form/fields/FieldEditor/types.ts'
import type { FormFieldContext } from '#shared/components/Form/types/field.ts'

import type { Extensions } from '@tiptap/core'
import type { Editor } from '@tiptap/vue-3'
import type { Ref, ShallowRef } from 'vue'

export const lowlight = createLowlight(common)

export const getPlainExtensions = (): Extensions => [
  StarterKit.configure({
    blockquote: false,
    bold: false,
    bulletList: false,
    code: false,
    codeBlock: false,
    dropcursor: false,
    gapcursor: false,
    heading: false,
    horizontalRule: false,
    italic: false,
    listItem: false,
    hardBreak: false,
    orderedList: false,
    strike: false,
    link: {
      openOnClick: false,
      autolink: false,
    },
  }),
  CharacterCount,
  HardBreakPlain,
]

export const getHtmlExtensions = (): Extensions => [
  StarterKit.configure({
    blockquote: false,
    paragraph: false,
    codeBlock: false,
    link: false,
  }),
  Blockquote.extend({
    addAttributes() {
      return {
        ...this.parent?.(),
        type: {
          default: null,
        },
        'data-marker': {
          default: null,
        },
      }
    },
  }),
  CharacterCount,
  CodeBlockLowlight.configure({ lowlight }),
  Color,
  IndentExtension,
  MarginLeft.configure({
    types: ['listItem', 'taskItem', 'heading', 'paragraph'],
  }),
  MarginRight.configure({
    types: ['listItem', 'taskItem', 'heading', 'paragraph'],
  }),
  Paragraph.extend({
    addAttributes() {
      return {
        ...this.parent?.(),
        'data-marker': {
          default: null,
        },
      }
    },
  }),
  TextDirection.configure({
    defaultDirection: document.documentElement.getAttribute('dir') as Direction,
    types: ['paragraph', 'heading'],
  }),
  TableKit.configure({
    table: {
      resizable: true,
      allowTableNodeSelection: true,
    },
  }),
  Link,
  TextStyle,
  UserLink,
]

export const getCustomExtensions = (
  context: Ref<FormFieldContext<FieldEditorProps>>,
  editor: ShallowRef<Editor>,
): Extensions => [
  Image,
  Signature,
  UserMention(context),
  KnowledgeBaseSuggestion(context),
  TextModuleSuggestion(context),
  AiAssistantTextTools(editor),
]
