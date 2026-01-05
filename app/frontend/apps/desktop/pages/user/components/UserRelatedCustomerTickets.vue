<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { ref, watch } from 'vue'

import { EnumTicketStateTypeCategory, type User } from '#shared/graphql/types.ts'

import CommonDivider from '#desktop/components/CommonDivider/CommonDivider.vue'

import CustomerTicketList from './UserRelatedCustomerTickets/CustomerTicketList.vue'

interface Props {
  customer: User
  customerOrganizations?: boolean
}

defineProps<Props>()

const emit = defineEmits<{
  'total-count': [number]
}>()

const openTicketsCount = ref<number>()
const closedTicketsCount = ref<number>()

watch([openTicketsCount, closedTicketsCount], ([open, closed]) => {
  emit('total-count', (open ?? 0) + (closed ?? 0))
})
</script>

<template>
  <div class="flex flex-col gap-3">
    <CustomerTicketList
      :customer="customer"
      :label="__('Open tickets')"
      :state-type-category="EnumTicketStateTypeCategory.Open"
      :customer-organizations="customerOrganizations"
      @count="openTicketsCount = $event"
    />
    <CommonDivider />
    <CustomerTicketList
      :customer="customer"
      :label="__('Closed tickets')"
      :state-type-category="EnumTicketStateTypeCategory.Closed"
      :customer-organizations="customerOrganizations"
      @count="closedTicketsCount = $event"
    />
  </div>
</template>
