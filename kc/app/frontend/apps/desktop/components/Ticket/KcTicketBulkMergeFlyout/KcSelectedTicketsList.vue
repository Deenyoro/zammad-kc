<!-- KC: Displays selected tickets in the bulk merge flyout using TicketSimpleTable. -->

<script setup lang="ts">
import TicketSimpleTable from '#desktop/pages/ticket/components/TicketDetailView/TicketSimpleTable/TicketSimpleTable.vue'
import type { TicketRelationAndRecentListItem } from '#desktop/pages/ticket/components/TicketDetailView/TicketSimpleTable/types.ts'

interface Props {
  tickets: TicketRelationAndRecentListItem[]
  selectedTicketId?: string
}

defineProps<Props>()

const emit = defineEmits<{
  'click-ticket': [TicketRelationAndRecentListItem]
}>()
</script>

<template>
  <TicketSimpleTable
    v-if="tickets.length"
    :tickets="tickets"
    :label="__('Selected tickets')"
    :selected-ticket-id="selectedTicketId"
    @click-ticket="emit('click-ticket', $event)"
  />
</template>
