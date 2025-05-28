// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { type Component } from 'vue'

let actionBarComponent: Component

export const initializeEditorActionBarComponent = (component: Component) => {
  actionBarComponent = component
}
export const getEditorActionBarComponent = () => actionBarComponent
