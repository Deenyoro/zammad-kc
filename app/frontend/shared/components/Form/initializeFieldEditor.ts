// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { type Component } from 'vue'

import type { FieldEditorClass } from './types.ts'

// Provide your own map with the following keys, the values given here are just examples.
let editorClasses: FieldEditorClass = {
  actionBar: {
    tableMenuContainer: '',
    button: {
      base: '',
    },
  },
  input: {
    container: '',
  },
}

let editorComponents: Record<string, Component | null> = {
  actionBar: null,
  actionMenu: null,
  suggestionList: null,
}

export const initializeFieldEditorClasses = (classes: FieldEditorClass) => {
  editorClasses = classes
}

export const getFieldEditorClasses = () => editorClasses

export const initializeEditorComponents = (components: Record<string, Component>) => {
  editorComponents = components
}

export const getEditorComponents = () => editorComponents
