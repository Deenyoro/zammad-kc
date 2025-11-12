// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { defineStore } from 'pinia'
import { effectScope, ref } from 'vue'

import { useTranslationsLazyQuery } from '#shared/graphql/queries/translations.api.ts'
import type { TranslationsQuery, TranslationsQueryVariables } from '#shared/graphql/types.ts'
import { i18n } from '#shared/i18n.ts'
import { QueryHandler } from '#shared/server/apollo/handler/index.ts'
import { useApplicationStore } from '#shared/stores/application.ts'
import log from '#shared/utils/log.ts'

interface TranslationsCacheValue {
  cacheKey: string
  translations: Record<string, string>
  locale: string
}

export const LOCAL_STORAGE_KEY = 'translationsStoreCache'

const loadCache = (locale: string): TranslationsCacheValue => {
  const cached = JSON.parse(window.localStorage.getItem(LOCAL_STORAGE_KEY) || '{}')

  log.debug('translations.loadCache()', locale, cached)

  return {
    cacheKey: cached.cacheKey || '',
    translations: cached.translations || {},
    locale: cached.locale || '',
  }
}

const setCache = (locale: string, value: TranslationsCacheValue): void => {
  const serialized = JSON.stringify(value)

  window.localStorage.setItem(LOCAL_STORAGE_KEY, serialized)

  log.debug('translations.setCache()', locale, value)
}

let translationsQuery: QueryHandler<TranslationsQuery, TranslationsQueryVariables>

const getTranslationsQuery = () => {
  if (translationsQuery) return translationsQuery

  const scope = effectScope()

  scope.run(() => {
    translationsQuery = new QueryHandler(
      useTranslationsLazyQuery({} as TranslationsQueryVariables),
      {
        // Don't show an error while app is loading as this would cause startup failure.
        errorShowNotification: useApplicationStore().loaded,
      },
    )
  })

  return translationsQuery
}

export const useTranslationsStore = defineStore(
  'translations',
  () => {
    const cacheKey = ref<string>('CACHE_EMPTY')
    const translationData = ref<Record<string, string>>({})

    const load = async (newLocale: string): Promise<void> => {
      log.debug('translations.load()', newLocale)

      const cachedData = loadCache(newLocale)

      const translationsQuery = getTranslationsQuery()

      const { data: result } = await translationsQuery.query({
        variables: {
          cacheKey: cachedData.cacheKey,
          locale: newLocale,
        },
      })

      if (!result?.translations) {
        return
      }

      if (result.translations.isCacheStillValid && cachedData.locale === newLocale) {
        cacheKey.value = cachedData.cacheKey
        translationData.value = cachedData.translations
      } else {
        cacheKey.value = result.translations.cacheKey || 'CACHE_EMPTY'
        translationData.value = result.translations.translations

        setCache(newLocale, {
          cacheKey: cacheKey.value,
          translations: translationData.value,
          locale: newLocale,
        })
      }

      i18n.setTranslationMap(new Map(Object.entries(translationData.value)))

      log.debug('translations.load() setting new translation map', newLocale, translationData.value)
    }

    return {
      cacheKey,
      translationData,
      load,
    }
  },
  {
    requiresAuth: false,
  },
)
