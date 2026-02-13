<!-- KC: Wrapper component for the scheduled replies sidebar.
     Follows the upstream TicketSidebarChecklist pattern.
     Badge is intentionally omitted — the content component owns the
     composable instance and API calls; duplicating it here would cause
     double-fetches and stale badge data. -->

<script setup lang="ts">
import { onMounted } from 'vue'

import { usePersistentStates } from '#desktop/pages/ticket/composables/usePersistentStates.ts'
import {
  type TicketSidebarProps,
  type TicketSidebarEmits,
} from '#desktop/pages/ticket/types/sidebar.ts'

import TicketSidebarWrapper from '../TicketSidebarWrapper.vue'

import TicketSidebarKcScheduledRepliesContent from './TicketSidebarKcScheduledRepliesContent.vue'

defineProps<TicketSidebarProps>()

const { persistentStates } = usePersistentStates()

const emit = defineEmits<TicketSidebarEmits>()

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
  >
    <TicketSidebarKcScheduledRepliesContent
      v-model="persistentStates"
      :context="context"
      :sidebar-plugin="sidebarPlugin"
    />
  </TicketSidebarWrapper>
</template>
