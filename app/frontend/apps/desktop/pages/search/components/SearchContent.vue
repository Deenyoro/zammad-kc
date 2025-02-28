<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { useRouteParams, useRouteQuery } from '@vueuse/router'
import { computed, ref, useTemplateRef, watch, type Ref, nextTick } from 'vue'

import { useSorting } from '#shared/composables/list/useSorting.ts'
import {
  type EnumOrderDirection,
  EnumSearchableModels,
} from '#shared/graphql/types.ts'
import { QueryHandler } from '#shared/server/apollo/handler/index.ts'

import LayoutContent from '#desktop/components/layout/LayoutContent.vue'
import { useDetailSearchLazyQuery } from '#desktop/components/Search/graphql/queries/detailSearch.api.ts'
import { useSearchCountsLazyQuery } from '#desktop/components/Search/graphql/queries/searchCounts.api.ts'
import {
  searchPluginByName,
  useSearchPlugins,
} from '#desktop/components/Search/plugins/index.ts'
import { useElementScroll } from '#desktop/composables/useElementScroll.ts'
import SearchControls from '#desktop/pages/search/components/SearchControls.vue'
import SearchEmptyMessage from '#desktop/pages/search/components/SearchEmptyMessage.vue'

import type { CustomSorting } from '../types/sorting.ts'

const MAX_ITEMS = 1000
const PAGE_SIZE = 30

const modelSearchTerm = useRouteParams('searchTerm', undefined, {
  mode: 'push',
})
const selectedEntity = useRouteQuery<EnumSearchableModels>(
  'entity',
  EnumSearchableModels.Ticket,
  { mode: 'replace' },
)

const searchTerm = computed(() => modelSearchTerm.value ?? '')

const scrollContainer = useTemplateRef('scroll-container')
const { reachedTop } = useElementScroll(scrollContainer as Ref<HTMLElement>)

const searchControlsInstance = useTemplateRef('search-controls')

const { sortedByNamePlugins, searchPluginNames } = useSearchPlugins()

const detailSearchQuery = new QueryHandler(
  useDetailSearchLazyQuery(
    () => ({
      search: searchTerm.value ?? '',
      limit: PAGE_SIZE,
      onlyIn: selectedEntity.value,
      offset: 0,
    }),
    {
      context: {
        batch: {
          active: false,
        },
      },
      fetchPolicy: 'no-cache',
    },
  ),
)

const notVisibleSearchEntities = computed(() =>
  searchPluginNames.value.filter((name) => name !== selectedEntity.value),
)

let staticNotVisibleSearchEntities = notVisibleSearchEntities.value

watch(notVisibleSearchEntities, (newValue) => {
  staticNotVisibleSearchEntities = newValue
})

const searchCountsQuery = new QueryHandler(
  useSearchCountsLazyQuery(
    () => {
      return {
        search: searchTerm.value,
        onlyIn: staticNotVisibleSearchEntities,
      }
    },
    () => ({
      context: {
        batch: {
          active: false,
        },
      },
      fetchPolicy: 'no-cache',
      enabled: searchPluginNames.value.length > 1,
    }),
  ),
)

const searchQueriesLoad = () => {
  detailSearchQuery.load()
  searchCountsQuery.load()
}

const searchQueriesStart = () => {
  detailSearchQuery.start()
  searchCountsQuery.start()
}

const searchQueriesStop = () => {
  detailSearchQuery.stop()
  searchCountsQuery.stop()
}

const searchEntityManualSorting = ref<
  Partial<Record<EnumSearchableModels, CustomSorting>>
>({})
const searchEntityLastCounts = ref<
  Partial<Record<EnumSearchableModels, number>>
>({})

const searchPlugin = computed(() => searchPluginByName[selectedEntity.value])

watch(
  searchTerm,
  (newValue, oldValue) => {
    if (newValue && detailSearchQuery.isFirstRun()) {
      searchQueriesLoad()
      return
    }

    if (oldValue && !newValue) searchQueriesStop()
    else if (newValue && !oldValue) nextTick(searchQueriesStart)
  },
  { immediate: true },
)

const searchResult = detailSearchQuery.result()
const loading = detailSearchQuery.loading()

const searchCountsResult = searchCountsQuery.result()

const searchCounts = computed(() =>
  searchCountsResult.value?.searchCounts.reduce(
    (acc, curr) => {
      acc[curr.model] = curr.totalCount
      return acc
    },
    {} as Record<EnumSearchableModels, number>,
  ),
)

// TODO: Check whats the best loading behavior for the different situations:
// e.g. swichting entity, because the result is currently still present

// const isLoading = computed(() => {
//   if (searchResult.value !== undefined) return false

//   return loading.value
// })

const searchResultTotalCount = computed(
  () => searchResult.value?.search.totalCount ?? 0,
)
const searchResultItems = computed(() => searchResult.value?.search.items || [])

watch(searchResultTotalCount, (newValue) => {
  searchEntityLastCounts.value[selectedEntity.value] = newValue
})

const searchTabs = computed(() =>
  sortedByNamePlugins.value.map((plugin) => {
    let count =
      searchCounts.value?.[plugin.name] ??
      (searchEntityLastCounts.value[plugin.name] || 0)

    if (plugin.name === selectedEntity.value) {
      count = searchResultTotalCount.value
    }

    return {
      label: plugin.label,
      key: plugin.name,
      count,
    }
  }),
)

const activeTabSortingOrderBy = computed(
  () => searchEntityManualSorting.value[selectedEntity.value]?.orderBy,
)
const activeTabSortingOrderDirection = computed(
  () => searchEntityManualSorting.value[selectedEntity.value]?.orderDirection,
)

const { sort, orderBy, orderDirection, isSorting } = useSorting(
  detailSearchQuery,
  activeTabSortingOrderBy,
  activeTabSortingOrderDirection,
  scrollContainer,
)

const resort = (column: string, direction: EnumOrderDirection) => {
  searchEntityManualSorting.value[selectedEntity.value] = {
    orderBy: column,
    orderDirection: direction,
  }
  sort(column, direction)
}

const maxPageSize = computed(() => searchResultTotalCount.value / PAGE_SIZE)
const offset = ref(0)
const loadingNewPage = ref(false)

const fetchNextPage = async () => {
  if (maxPageSize.value <= offset.value) return

  offset.value += PAGE_SIZE

  loadingNewPage.value = true

  try {
    await detailSearchQuery.fetchMore({
      variables: {
        limit: PAGE_SIZE,
        offset: offset.value,
      },
      updateQuery(previousQuery, { fetchMoreResult }) {
        if (!fetchMoreResult) return previousQuery

        const newResult = fetchMoreResult.search

        return {
          ...previousQuery,
          search: {
            totalCount: newResult.totalCount,
            items: [...previousQuery.search.items, ...newResult.items],
          },
        }
      },
    })
  } finally {
    loadingNewPage.value = false
  }
}

// TODO: Pagination needs to be resetet after entity switch or remembered, clarify...

const resetPagination = () => {
  offset.value = 0
}

watch(searchTerm, () => {
  resetPagination()
  searchEntityManualSorting.value = {}
  searchEntityLastCounts.value = {}
})

const breadcrumbItems = computed(() => [
  { label: __('Search') },
  {
    label: __('Results'),
    isActive: true,
    count:
      searchResult.value !== undefined
        ? searchResultTotalCount.value
        : undefined,
  },
])
</script>

<template>
  <LayoutContent
    content-padding
    no-scrollable
    :breadcrumb-items="breadcrumbItems"
  >
    <template #headerRight></template>
    <div
      class="flex h-full flex-col overflow-hidden"
      data-test-id="search-container"
    >
      <SearchControls
        ref="search-controls"
        v-model:search="modelSearchTerm"
        v-model:selected-entity="selectedEntity"
        :search-tabs="searchTabs"
        class="px-4"
      />
      <div
        :id="`tab-panel-${selectedEntity}`"
        ref="scroll-container"
        class="relative grow overflow-y-auto px-4 pb-4"
      >
        <component
          :is="searchPlugin.detailSearchComponent"
          :table-id="`search-${selectedEntity}-table`"
          :caption="`Search result for: ${searchPlugin.label}`"
          :items="searchResultItems"
          :headers="searchPlugin.detailSearchHeaders"
          :total-count="searchResultTotalCount"
          :order-by="orderBy"
          :order-direction="orderDirection"
          :loading="loading"
          :resorting="isSorting"
          :max-items="MAX_ITEMS"
          :loading-new-page="loadingNewPage"
          :reached-scroll-top="reachedTop"
          :scroll-container="scrollContainer"
          @load-more="fetchNextPage"
          @sort="resort"
        >
          <template #empty-list>
            <SearchEmptyMessage
              class="absolute top-1/2 -translate-y-1/2 ltr:left-1/2 ltr:-translate-x-1/2 rtl:right-1/2 rtl:translate-x-1/2"
              :search-term="searchTerm"
              :results="searchResultItems"
              @clear-search-input="
                () => searchControlsInstance?.clearAndFocusSearch()
              "
            />
          </template>
        </component>
      </div>
    </div>
  </LayoutContent>
</template>
