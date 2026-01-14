// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import * as dateFnsLocales from 'date-fns/locale'
import { computed } from 'vue'

import { i18n } from '#shared/i18n/index.ts'

export const useDateFnsLocale = () => {
  const dateFnsLocale = computed(() => {
    const localeKey = i18n.locale()
    // date-fns locale keys use camelCase for country codes, e.g., 'enUS', 'zhCN'
    // i18n locale uses hyphen, e.g., 'en-us', 'zh-cn'
    // date-fns code vary in casing, so save match them by lowercasing both sides
    const entry = Object.entries(dateFnsLocales).find(
      ([, locale]) => locale.code.toLowerCase() === localeKey.toLowerCase(),
    )

    return entry ? entry[1] : dateFnsLocales.enUS
  })

  return { dateFnsLocale }
}
