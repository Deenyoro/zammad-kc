<!-- KC: Bulk merge button — shown in the ticket overview header when
     tickets are checked and kc_bulk_merge setting is enabled. -->

<script setup lang="ts">
import { computed } from 'vue'

import { useApplicationStore } from '#shared/stores/application.ts'
import { useSessionStore } from '#shared/stores/session.ts'

import CommonButton from '#desktop/components/CommonButton/CommonButton.vue'

interface Props {
  checkedTicketIds: Set<ID>
}

defineProps<Props>()

defineEmits<{
  'open-flyout': []
}>()

const { hasPermission } = useSessionStore()
const { config } = useApplicationStore()

const isVisible = computed(
  () => hasPermission('ticket.agent') && !!config.kc_bulk_merge,
)
</script>

<template>
  <CommonButton
    v-if="isVisible && checkedTicketIds.size"
    data-test-id="kc-ticket-bulk-merge-button"
    size="medium"
    prefix-icon="merge"
    variant="secondary"
    @click="$emit('open-flyout')"
    >{{ $t('Merge') }}</CommonButton
  >
</template>
