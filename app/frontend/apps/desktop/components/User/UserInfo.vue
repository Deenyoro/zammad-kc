<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import CommonUserAvatar from '#shared/components/CommonUserAvatar/CommonUserAvatar.vue'
import type { UserQuery } from '#shared/graphql/types.ts'

interface Props {
  user: UserQuery['user']
}

defineProps<Props>()
</script>

<template>
  <div class="flex gap-2">
    <CommonUserAvatar v-if="user" :entity="user" size="normal" />
    <div class="flex flex-col justify-center gap-px">
      <CommonLabel size="large" class="text-gray-300! dark:text-neutral-400!">
        {{ user?.fullname }}
      </CommonLabel>

      <CommonLink
        v-if="user?.organization"
        :link="`/organizations/${user.organization?.internalId}`"
        class="text-sm leading-snug"
      >
        {{ user?.organization.name }}
      </CommonLink>
    </div>
  </div>
</template>
