<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { onBeforeRouteUpdate } from 'vue-router'

import { EnumSearchableModels } from '#shared/graphql/types.ts'

import LayoutTaskbarTabContent from '#desktop/components/layout/LayoutTaskbarTabContent.vue'
import SearchContent from '#desktop/pages/search/components/SearchContent.vue'

interface Props {
  searchTerm: string
}

defineOptions({
  beforeRouteEnter(to, _, next) {
    return to.query.entity
      ? next()
      : next({ ...to, query: { entity: EnumSearchableModels.Ticket } })
  },
})

onBeforeRouteUpdate((to, _, next) => {
  return to.query.entity
    ? next()
    : next({ ...to, query: { entity: EnumSearchableModels.Ticket } })
})

defineProps<Props>()
</script>

<template>
  <LayoutTaskbarTabContent>
    <SearchContent />
  </LayoutTaskbarTabContent>
</template>
