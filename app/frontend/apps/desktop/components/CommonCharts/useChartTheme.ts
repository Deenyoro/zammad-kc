// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { storeToRefs } from 'pinia'
import { computed, provide } from 'vue'
import { THEME_KEY } from 'vue-echarts'

import { EnumAppearanceTheme } from '#shared/graphql/types.ts'

import { useThemeStore } from '#desktop/stores/theme.ts'

export const useChartTheme = () => {
  const { isDarkMode } = storeToRefs(useThemeStore())

  const colorTheme = computed(() =>
    isDarkMode.value ? EnumAppearanceTheme.Dark : EnumAppearanceTheme.Light,
  )

  // ⚠️ seems to not update theme within the library component
  // Currently styling is handled within the computed options of chart
  provide(THEME_KEY, colorTheme)

  return { colorTheme }
}
