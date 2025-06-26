// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

export interface HighlightColor {
  value: {
    light: string
    dark: string
  }
  label: string
  name: string
  id: string
}

export interface PaletteColor {
  value: string
  label: string
}
