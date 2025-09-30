<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

import CommonOrganizationAvatar from '#shared/components/CommonOrganizationAvatar/CommonOrganizationAvatar.vue'
import type { OrganizationQuery } from '#shared/graphql/types.ts'

interface Props {
  organization: OrganizationQuery['organization']
  noLink?: boolean
}

const props = defineProps<Props>()

const component = computed(() => (props.noLink ? 'div' : 'CommonLink'))
</script>

<template>
  <div class="flex gap-2">
    <component
      :is="component"
      :class="{ 'hover:no-underline!': !noLink }"
      :link="!noLink ? `/organization/profile/${organization.internalId}` : undefined"
    >
      <CommonOrganizationAvatar class="p-3.5" :entity="organization" size="normal" />
    </component>
    <CommonLabel size="large">{{ organization.name }}</CommonLabel>
  </div>
</template>
