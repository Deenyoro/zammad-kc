<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { useDebounceFn } from '@vueuse/core'
import { computed, nextTick, useTemplateRef } from 'vue'

import CommonInputSearch from '#desktop/components/CommonInputSearch/CommonInputSearch.vue'
import CommonTabGroup from '#desktop/components/CommonTabGroup/CommonTabGroup.vue'
import type { Tab } from '#desktop/components/CommonTabGroup/types.ts'

const DEBOUNCE_TIME = 500

interface Props {
  searchTabs: Tab[]
}

defineProps<Props>()

const searchParam = defineModel<string>('search')

const selectedEntity = defineModel<string>('selected-entity', {
  default: 'Ticket',
})

const inputSearchInstance = useTemplateRef('search-input')

const searchTerm = computed({
  get: () => searchParam.value,
  set: useDebounceFn((value) => {
    searchParam.value = value
  }, DEBOUNCE_TIME),
})

const clearAndFocusSearch = () => {
  searchTerm.value = ''
  nextTick(() => {
    inputSearchInstance.value?.focus()
  })
}

defineExpose({
  clearAndFocusSearch,
})
</script>

<template>
  <div class="space-y-4 bg-neutral-50 pb-4 dark:bg-gray-500">
    <CommonInputSearch
      ref="search-input"
      v-model="searchTerm"
      wrapper-class="rounded-lg w-full bg-blue-200 px-2.5 py-2 -outline-offset-1 outline-blue-800 focus-within:outline dark:bg-gray-700"
    />

    <CommonTabGroup
      v-show="searchTabs.length > 1"
      v-model="selectedEntity"
      :multiple="false"
      :tabs="searchTabs"
    />
  </div>
</template>
