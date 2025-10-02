<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

import CommonOrganizationAvatar from '#shared/components/CommonOrganizationAvatar/CommonOrganizationAvatar.vue'
import type { OrganizationQuery } from '#shared/graphql/types.ts'

interface Props {
  organization: OrganizationQuery['organization']
  size?: 'small' | 'normal'
  dense?: boolean
  noLink?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  size: 'normal',
})

const avatarComponent = computed(() => (props.noLink || props.dense ? 'div' : 'CommonLink'))
const nameComponent = computed(() => (props.noLink && !props.dense ? 'div' : 'CommonLink'))

const labelSize = computed(() => (props.size === 'normal' ? 'large' : 'medium'))
</script>

<template>
  <div class="flex items-center gap-2">
    <component
      :is="avatarComponent"
      :class="{ 'hover:no-underline!': !noLink }"
      :link="!dense && !noLink ? `/organization/profile/${organization.internalId}` : undefined"
    >
      <CommonOrganizationAvatar :entity="organization" :size="size" />
    </component>
    <component
      :is="nameComponent"
      v-if="dense"
      :class="{ 'hover:no-underline!': !noLink }"
      :link="dense && !noLink ? `/organization/profile/${organization.internalId}` : undefined"
    >
      <CommonLabel :size="labelSize" :class="{ 'text-blue-800!': !noLink }">
        {{ organization.name }}
      </CommonLabel>
    </component>
    <CommonLabel v-else :size="labelSize">{{ organization.name }}</CommonLabel>
  </div>
</template>
