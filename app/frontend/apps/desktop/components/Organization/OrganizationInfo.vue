<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed, toRef } from 'vue'

import type { Sizes } from '#shared/components/CommonLabel/types.ts'
import CommonOrganizationAvatar from '#shared/components/CommonOrganizationAvatar/CommonOrganizationAvatar.vue'
import type { AvatarOrganization } from '#shared/components/CommonOrganizationAvatar/types.ts'
import { useOrganizationEntity } from '#shared/entities/organization/composables/useOrganizationEntity.ts'
import type { Organization } from '#shared/graphql/types.ts'

interface Props {
  organization: Partial<Organization>
  size?: 'small' | 'normal'
  dense?: boolean
  noLink?: boolean
  titleSize?: Sizes
  titleClass?: string
}

const props = withDefaults(defineProps<Props>(), {
  size: 'normal',
})

const avatarComponent = computed(() => (props.noLink || props.dense ? 'div' : 'CommonLink'))
const nameComponent = computed(() => (props.noLink && !props.dense ? 'div' : 'CommonLink'))

const labelSize = computed(() => (props.size === 'normal' ? 'large' : 'medium'))

const { organizationDisplayName } = useOrganizationEntity(toRef(props, 'organization'))
</script>

<template>
  <div class="flex items-center w-full" :class="{ 'gap-2': !titleSize, 'gap-3': titleSize }">
    <component
      :is="avatarComponent"
      :class="{
        'hover:no-underline! hover:rounded-full hover:outline-1 hover:outline-blue-600 hover:dark:outline-blue-900 focus-visible:rounded-full!':
          !dense && !noLink,
      }"
      :link="!dense && !noLink ? `/organizations/${organization.internalId}` : undefined"
    >
      <CommonOrganizationAvatar :entity="organization as AvatarOrganization" :size="size" />
    </component>
    <component
      :is="nameComponent"
      v-if="dense"
      :class="{ group: !noLink }"
      :link="dense && !noLink ? `/organizations/${organization.internalId}` : undefined"
    >
      <CommonLabel
        :class="{
          [`${titleClass}`]: titleClass,
          'text-blue-800! group-hover:text-blue-850! group-hover:dark:text-blue-600!': !noLink,
        }"
        :size="titleSize ? titleSize : labelSize"
      >
        {{ organizationDisplayName }}
      </CommonLabel>
    </component>
    <CommonLabel v-else :class="titleClass" :size="titleSize ? titleSize : labelSize">
      {{ organizationDisplayName }}
    </CommonLabel>
  </div>
</template>
