<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed, toRef } from 'vue'

import { useTicketLiveUsersDisplay } from '#shared/entities/ticket/composables/useTicketLiveUsersDisplay.ts'
import type { TicketLiveAppUser } from '#shared/entities/ticket/types.ts'

import UserPopoverWithTrigger from '#desktop/components/User/UserPopoverWithTrigger.vue'

export interface Props {
  liveUserList: TicketLiveAppUser[]
}

const props = defineProps<Props>()

const { liveUsers } = useTicketLiveUsersDisplay(toRef(props, 'liveUserList'))

const LIVE_USER_LIMIT = 9

const visibleLiveUsers = computed(() =>
  liveUsers.value.slice(0, LIVE_USER_LIMIT),
)

const liveUsersOverflow = computed(() => {
  if (liveUsers.value.length <= LIVE_USER_LIMIT) return
  const overflow = liveUsers.value.length - LIVE_USER_LIMIT
  if (overflow > 999) return '+999'
  return `+${overflow}`
})
</script>

<template>
  <div class="flex items-center gap-2">
    <UserPopoverWithTrigger
      v-for="liveUser in visibleLiveUsers"
      :key="liveUser.user.id"
      :user="liveUser.user"
      :avatar-config="{
        live: liveUser,
        size: 'small',
      }"
      :popover-config="{
        placement: 'arrowStart',
      }"
    />
    <div
      v-if="liveUsersOverflow"
      class="flex h-8 w-8 items-center justify-center rounded-full bg-blue-200 text-sm outline-1 -outline-offset-1 outline-neutral-100 dark:bg-gray-700 dark:outline-gray-900"
    >
      {{ liveUsersOverflow }}
    </div>
  </div>
</template>
