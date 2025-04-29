<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

import { type Props as CommonPopoverProps } from '#shared/components/CommonPopover/CommonPopover.vue'
import CommonUserAvatar, {
  type Props as CommonUserAvatarProps,
} from '#shared/components/CommonUserAvatar/CommonUserAvatar.vue'
import type { AvatarUser } from '#shared/components/CommonUserAvatar/types.ts'
import { getIdFromGraphQLId } from '#shared/graphql/utils.ts'

import CommonPopoverWithTrigger from '#desktop/components/CommonPopover/CommonPopoverWithTrigger.vue'
import UserPopover from '#desktop/components/User/UserPopoverWithTrigger/UserPopover.vue'

export interface Props {
  user: AvatarUser
  popoverConfig?: Omit<CommonPopoverProps, 'owner'>
  avatarConfig?: Omit<CommonUserAvatarProps, 'entity'>
  triggerClass?: string
  noLink?: boolean
  noFocusStyling?: boolean
}

const props = defineProps<Props>()

const userInternalId = computed(() => getIdFromGraphQLId(props.user.id))
</script>

<template>
  <CommonPopoverWithTrigger
    :class="[
      !$slots?.default?.() ? 'rounded-full! focus-visible:outline-2!' : '',
      triggerClass ?? '',
    ]"
    :no-focus-styling="noFocusStyling"
    :trigger-link="!noLink ? `/user/profile/${userInternalId}` : undefined"
    :trigger-link-active-class="
      !$slots?.default?.()
        ? 'outline-2! outline-offset-1! outline-blue-800! hover:outline-blue-800!'
        : ''
    "
    v-bind="popoverConfig"
  >
    <template #popover-content="{ popoverId }">
      <UserPopover :id="popoverId" :user-avatar="user" />
    </template>

    <template #default="slotProps">
      <slot v-bind="slotProps">
        <CommonUserAvatar v-bind="avatarConfig" :entity="user" />
      </slot>
    </template>
  </CommonPopoverWithTrigger>
</template>
