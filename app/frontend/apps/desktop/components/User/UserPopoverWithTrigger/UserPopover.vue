<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { toRef } from 'vue'

import type { AvatarUser } from '#shared/components/CommonUserAvatar/types.ts'
import ObjectAttributes from '#shared/components/ObjectAttributes/ObjectAttributes.vue'
import { useDebouncedLoading } from '#shared/composables/useDebouncedLoading.ts'
import { useUserDetail } from '#shared/entities/user/composables/useUserDetail.ts'

import CommonSimpleEntityList from '#desktop/components/CommonSimpleEntityList/CommonSimpleEntityList.vue'
import { EntityType } from '#desktop/components/CommonSimpleEntityList/types.ts'
import UserInfo from '#desktop/components/User/UserInfo.vue'
import UserPopoverSkeleton from '#desktop/components/User/UserPopoverWithTrigger/skeleton/UserPopoverSkeleton.vue'

interface Props {
  userAvatar: AvatarUser
}

const props = defineProps<Props>()

const { user, loading, secondaryOrganizations, objectAttributes } =
  useUserDetail(toRef(props.userAvatar.id))

const { debouncedLoading } = useDebouncedLoading({
  isLoading: loading,
})
</script>

<template>
  <section ref="popover-section" data-type="popover" class="space-y-2 p-3">
    <UserPopoverSkeleton v-if="debouncedLoading && !user" />
    <template v-else>
      <UserInfo :user="user!" />

      <ObjectAttributes
        :class="{
          'border-b border-white pb-2.5 dark:border-black':
            secondaryOrganizations?.totalCount,
        }"
        :object="user!"
        :attributes="objectAttributes"
        :skip-attributes="['firstname', 'lastname', 'organization_id']"
      />

      <CommonSimpleEntityList
        v-if="secondaryOrganizations?.totalCount"
        id="customer-secondary-organizations-popover"
        no-collapse
        :type="EntityType.Organization"
        :label="__('Secondary organizations')"
        :entity="secondaryOrganizations"
      >
        <template #trailing="{ totalCount, entities }">
          <CommonLink
            v-if="totalCount - entities.length"
            class="float-right mt-2 inline-block"
            size="small"
            internal
            :link="`/user/${user!.internalId}`"
            >{{ $t('%s more', totalCount - entities.length) }}</CommonLink
          >
        </template>
      </CommonSimpleEntityList>
    </template>
  </section>
</template>
