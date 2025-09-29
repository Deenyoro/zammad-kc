<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import type { UserQuery } from '#shared/graphql/types.ts'

import UserInfo from '#desktop/components/User/UserInfo.vue'

interface Props {
  users: UserQuery['user'][]
}

defineProps<Props>()
</script>

<template>
  <section ref="popover-section" data-type="popover" class="flex flex-col gap-2.5 p-3">
    <UserInfo v-for="user in users" :key="user.id" :user="user!" size="small" dense />
  </section>
</template>
