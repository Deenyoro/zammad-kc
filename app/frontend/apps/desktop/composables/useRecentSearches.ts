// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { useLocalStorage } from '@vueuse/core'

import { useSessionStore } from '#shared/stores/session.ts'

const RECENTLY_SEARCHES_MAX_LENGTH = 10

export const useRecentSearches = () => {
  const { userId } = useSessionStore()
  const recentSearches = useLocalStorage<string[]>(
    `${userId}-recentSearches`,
    [],
  )

  const addSearch = (search: string) => {
    // Remove the search term if it already exists to avoid duplicates
    recentSearches.value = recentSearches.value.filter(
      (item) => item !== search,
    )

    // Add the new search term
    recentSearches.value.push(search)

    // Remove the oldest search if we exceed the maximum length
    if (recentSearches.value.length > RECENTLY_SEARCHES_MAX_LENGTH) {
      recentSearches.value.shift()
    }
  }

  const removeSearch = (search: string) => {
    recentSearches.value = recentSearches.value.filter(
      (item) => item !== search,
    )
  }

  const clearSearches = () => {
    recentSearches.value = []
  }

  return {
    recentSearches,
    addSearch,
    removeSearch,
    clearSearches,
  }
}
