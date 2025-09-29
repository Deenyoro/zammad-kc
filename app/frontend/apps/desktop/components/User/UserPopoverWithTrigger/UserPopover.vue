<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { toRef } from 'vue'
import { useRouter } from 'vue-router'

import type { AvatarUser } from '#shared/components/CommonUserAvatar/types.ts'
import ObjectAttributes from '#shared/components/ObjectAttributes/ObjectAttributes.vue'
import { useDebouncedLoading } from '#shared/composables/useDebouncedLoading.ts'
import { useUserDetail } from '#shared/entities/user/composables/useUserDetail.ts'

import CommonButton from '#desktop/components/CommonButton/CommonButton.vue'
import CommonSimpleEntityList from '#desktop/components/CommonSimpleEntityList/CommonSimpleEntityList.vue'
import { EntityType } from '#desktop/components/CommonSimpleEntityList/types.ts'
import UserInfo from '#desktop/components/User/UserInfo.vue'
import UserPopoverSkeleton from '#desktop/components/User/UserPopoverWithTrigger/skeleton/UserPopoverSkeleton.vue'

interface Props {
  userAvatar: AvatarUser
}

const props = defineProps<Props>()

const { user, loading, secondaryOrganizations, objectAttributes } = useUserDetail(
  toRef(props.userAvatar.id),
)

const { debouncedLoading } = useDebouncedLoading({
  isLoading: loading,
})

const router = useRouter()

const goToUserProfile = () => {
  if (!user.value) return

  router.push(`/user/profile/${user.value.internalId}`)
}
</script>

<template>
  <section ref="popover-section" data-type="popover" class="space-y-2 p-3">
    <UserPopoverSkeleton v-if="debouncedLoading && !user" />
    <template v-else>
      <UserInfo :user="user!" />

      <ObjectAttributes
        :class="{
          'border-b border-neutral-100 dark:border-gray-900 pb-2.5':
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
          <CommonButton
            v-if="totalCount - entities.length"
            class="self-end"
            variant="secondary"
            size="small"
            @click="goToUserProfile"
          >
            {{ $t('%s more', totalCount - entities.length) }}
          </CommonButton>
        </template>
      </CommonSimpleEntityList>
    </template>
  </section>
</template>
