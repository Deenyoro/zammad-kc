<!-- KC: Wrapper component for the scheduled replies sidebar.
     Follows the upstream TicketSidebarChecklist pattern. The wrapper is
     always mounted (it renders the sidebar tab button), so it owns the
     composable instance: the tab shows a badge with the number of pending
     scheduled replies, and the content component reuses the same instance
     (no double fetch, no stale badge). -->

<script setup lang="ts">
import { computed, onMounted, watch } from 'vue'

import { usePersistentStates } from '#desktop/pages/ticket/composables/usePersistentStates.ts'
import { useTicketInformation } from '#desktop/pages/ticket/composables/useTicketInformation.ts'
import {
  type TicketSidebarProps,
  type TicketSidebarEmits,
  TicketSidebarButtonBadgeType,
  type TicketSidebarButtonBadgeDetails,
} from '#desktop/pages/ticket/types/sidebar.ts'

import TicketSidebarWrapper from '../TicketSidebarWrapper.vue'

import TicketSidebarKcScheduledRepliesContent from './TicketSidebarKcScheduledRepliesContent.vue'
import { useKcScheduledReplies } from './useKcScheduledReplies.ts'

defineProps<TicketSidebarProps>()

const { persistentStates } = usePersistentStates()

const emit = defineEmits<TicketSidebarEmits>()

const { ticket, ticketInternalId } = useTicketInformation()

const replies = useKcScheduledReplies(ticketInternalId)

// A scheduled reply that went out (or any other ticket change) updates the
// ticket: refresh the list so the badge does not keep counting it.
watch(
  () => ticket.value?.updatedAt,
  (updatedAt, previous) => {
    if (updatedAt && previous && updatedAt !== previous) {
      replies.loadScheduledArticles()
    }
  },
)

const badge = computed<TicketSidebarButtonBadgeDetails | undefined>(() => {
  if (!replies.pendingCount.value) return

  return {
    type: TicketSidebarButtonBadgeType.Default,
    value: replies.pendingCount.value,
    label: __('Pending scheduled replies'),
  }
})

onMounted(() => {
  emit('show')
})
</script>

<template>
  <TicketSidebarWrapper
    :key="sidebar"
    :sidebar="sidebar"
    :sidebar-plugin="sidebarPlugin"
    :selected="selected"
    :badge="badge"
  >
    <TicketSidebarKcScheduledRepliesContent
      v-model="persistentStates"
      :context="context"
      :sidebar-plugin="sidebarPlugin"
      :replies="replies"
    />
  </TicketSidebarWrapper>
</template>
