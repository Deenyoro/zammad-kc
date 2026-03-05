<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { storeToRefs } from 'pinia'
import { computed } from 'vue'

import { useSessionStore } from '#shared/stores/session.ts'

import CommonButton from '#desktop/components/CommonButton/CommonButton.vue'
import { useTicketBulkUpdateStore } from '#desktop/entities/user/current/stores/ticketBulkUpdate.ts'

interface Props {
  checkedTicketIds: Set<ID>
}

defineProps<Props>()

defineEmits<{
  'open-flyout': []
}>()

const { hasPermission } = useSessionStore()

const isAgentUser = computed(() => hasPermission('ticket.agent'))

const { isRunning } = storeToRefs(useTicketBulkUpdateStore())

const buttonLabel = computed(() => (isRunning.value ? __('Bulk in progress…') : __('Bulk actions')))
const buttonVariant = computed(() => (isRunning.value ? 'neutral' : 'primary'))
</script>

<template>
  <CommonButton
    v-if="isAgentUser && checkedTicketIds.size"
    data-test-id="ticket-bulk-edit-button"
    size="medium"
    prefix-icon="collection-play"
    :variant="buttonVariant"
    :disabled="isRunning"
    @click="$emit('open-flyout')"
    >{{ $t(buttonLabel) }}</CommonButton
  >
</template>
