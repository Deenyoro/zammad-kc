<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'
import { useRouter } from 'vue-router'

import { useDebouncedLoading } from '#shared/composables/useDebouncedLoading.ts'
import type { CustomerTicketsByFilterQueryVariables } from '#shared/graphql/types.ts'
import { getIdFromGraphQLId } from '#shared/graphql/utils.ts'
import QueryHandler from '#shared/server/apollo/handler/QueryHandler.ts'
import { normalizeEdges } from '#shared/utils/helpers.ts'

import CommonSimpleEntityList from '#desktop/components/CommonSimpleEntityList/CommonSimpleEntityList.vue'
import { EntityType } from '#desktop/components/CommonSimpleEntityList/types.ts'
import { useCustomerTicketsByFilterQuery } from '#desktop/entities/ticket/graphql/queries/customerTicketsByFilter.api.ts'

import TicketListPopoverSkeleton from './skeleton/TicketListPopoverSkeleton.vue'

interface Props {
  filters: CustomerTicketsByFilterQueryVariables
  title: string
  searchLink?: string
  noResults?: boolean
}

const props = defineProps<Props>()

const ticketsByFilterQuery = new QueryHandler(
  useCustomerTicketsByFilterQuery(
    () => props.filters,
    () => ({ enabled: !props.noResults, fetchPolicy: 'cache-and-network' }),
  ),
)

const ticketsByFilterResult = ticketsByFilterQuery.result()
const loading = ticketsByFilterQuery.loading()
const tickets = computed(() => normalizeEdges(ticketsByFilterResult.value?.ticketsByFilter))

const { debouncedLoading } = useDebouncedLoading({
  isLoading: loading,
})

const router = useRouter()

const goToUserProfile = () => {
  if (!props.filters.customerId) return

  router.push(`/users/${getIdFromGraphQLId(props.filters.customerId)}`)
}
</script>

<template>
  <section ref="popover-section" data-type="popover" class="px-3 py-2 flex flex-col">
    <TicketListPopoverSkeleton v-if="debouncedLoading && !tickets.array.length" />
    <CommonSimpleEntityList
      v-else
      id="ticket-list-popover"
      :type="EntityType.Ticket"
      :label="title"
      :entity="tickets"
      no-collapse
      @load-more="goToUserProfile"
    />
  </section>
</template>
