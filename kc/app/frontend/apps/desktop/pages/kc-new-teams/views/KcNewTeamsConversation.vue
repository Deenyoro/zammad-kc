<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<!-- KC: New Teams message conversation - one draft, i.e. one taskbar tab, per tab id
     (like the ticket create screen). -->

<script setup lang="ts">
import LayoutTaskbarTabContent from '#desktop/components/layout/LayoutTaskbarTabContent.vue'

import KcNewTeamsConversationContent from '../components/KcNewTeamsConversationContent.vue'

interface Props {
  tabId: string
}

defineProps<Props>()
</script>

<template>
  <LayoutTaskbarTabContent>
    <KcNewTeamsConversationContent />
  </LayoutTaskbarTabContent>
</template>
