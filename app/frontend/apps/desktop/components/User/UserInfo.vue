<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

import CommonUserAvatar from '#shared/components/CommonUserAvatar/CommonUserAvatar.vue'
import type { UserQuery } from '#shared/graphql/types.ts'
import { getIdFromGraphQLId } from '#shared/graphql/utils.ts'

interface Props {
  user: UserQuery['user']
  size?: 'small' | 'normal'
  dense?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  size: 'normal',
})

const labelSize = computed(() => (props.size === 'normal' ? 'large' : 'medium'))
</script>

<template>
  <div class="flex items-center gap-2">
    <CommonUserAvatar v-if="user" :entity="user" :size="size" />
    <div class="flex flex-col justify-center gap-px">
      <CommonLink
        v-if="dense"
        :link="`/user/profile/${getIdFromGraphQLId(user.id)}`"
        class="text-sm leading-snug"
      >
        <CommonLabel :size="labelSize" class="text-blue-800!">
          {{ user.fullname }}
        </CommonLabel>
      </CommonLink>
      <CommonLabel v-else :size="labelSize" class="text-gray-300! dark:text-neutral-400!">
        {{ user.fullname }}
      </CommonLabel>

      <CommonLabel
        v-if="dense && user.email"
        :size="labelSize"
        class="text-gray-300! dark:text-neutral-400!"
      >
        {{ user.email }}
      </CommonLabel>
      <CommonLink
        v-else-if="user.organization"
        :link="`/organizations/${user.organization?.internalId}`"
      >
        <CommonLabel :size="labelSize" class="text-blue-800!">
          {{ user.organization.name }}
        </CommonLabel>
      </CommonLink>
    </div>
  </div>
</template>
