// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import type { Component } from 'vue'

let ActionMenu: Component

export const initializeEditorActionMenu = (component: Component) => {
  ActionMenu = component
}

export const getEditorActionMenu = () => ActionMenu
