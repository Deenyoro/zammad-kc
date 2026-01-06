<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { EnumTicketStateTypeCategory, type Organization } from '#shared/graphql/types.ts'

import CommonDivider from '#desktop/components/CommonDivider/CommonDivider.vue'

import OrganizationTicketList from './OrganizationRelatedTickets/OrganizationTicketList.vue'

interface Props {
  organization: Organization
}

defineProps<Props>()
</script>

<template>
  <div class="flex flex-col gap-3">
    <OrganizationTicketList
      :organization="organization"
      :label="__('Open tickets')"
      :state-type-category="EnumTicketStateTypeCategory.Open"
    />
    <CommonDivider />
    <OrganizationTicketList
      :organization="organization"
      :label="__('Closed tickets')"
      :state-type-category="EnumTicketStateTypeCategory.Closed"
    />
  </div>
</template>
