<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { storeToRefs } from 'pinia'
import { computed, useTemplateRef } from 'vue'

import ObjectAttributes from '#shared/components/ObjectAttributes/ObjectAttributes.vue'
import { useUserEntity } from '#shared/entities/user/composables/useUserEntity.ts'
import { useUserNoteUpdateMutation } from '#shared/entities/user/graphql/mutations/noteUpdate.api.ts'
import { useUserQuery } from '#shared/entities/user/graphql/queries/user.api.ts'
import { useUserObjectAttributesStore } from '#shared/entities/user/stores/objectAttributes.ts'
import type { User } from '#shared/graphql/types.ts'
import { convertToGraphQLId } from '#shared/graphql/utils.ts'
import { QueryHandler } from '#shared/server/apollo/handler/index.ts'

import CommonLoader from '#desktop/components/CommonLoader/CommonLoader.vue'
import CommonSkeleton from '#desktop/components/CommonSkeleton/CommonSkeleton.vue'
import LayoutContent from '#desktop/components/layout/LayoutContent.vue'
import { usePage } from '#desktop/composables/usePage.ts'
import { useScrollPosition } from '#desktop/composables/useScrollPosition.ts'

import UserDetailTopBar from './UserDetailTopBar.vue'

interface Props {
  internalId: string
}

const props = defineProps<Props>()

const userId = computed(() => convertToGraphQLId('User', props.internalId))

const userQuery = new QueryHandler(
  useUserQuery(
    () => ({
      userId: userId.value,
    }),
    () => ({
      fetchPolicy: 'cache-first',
    }),
  ),
)

const userResult = userQuery.result()
const loading = userQuery.loading()

const user = computed(() => userResult.value?.user as User)

const { userDisplayName } = useUserEntity(user)

const { viewScreenAttributes } = storeToRefs(useUserObjectAttributesStore())

usePage({
  metaTitle: userDisplayName,
})

const contentContainerElement = useTemplateRef('content-container')

useScrollPosition(contentContainerElement)
</script>

<template>
  <LayoutContent
    name="user-detail"
    no-padding
    background-variant="primary"
    content-alignment="center"
    no-scrollable
  >
    <CommonLoader class="mt-8" :loading="loading">
      <div ref="content-container" class="h-full w-full overflow-y-auto">
        <UserDetailTopBar
          :user="user"
          :user-display-name="userDisplayName"
          :content-container-element="contentContainerElement"
        />
        <section class="mx-auto w-full max-w-5xl grid grid-cols-2 gap-6 p-6">
          <ObjectAttributes
            :attributes="viewScreenAttributes"
            :object="user"
            :skip-attributes="['firstname', 'lastname', 'organization_id', 'organization_ids']"
            :inline-editable="{ note: useUserNoteUpdateMutation }"
          />
          <CommonSkeleton class="h-64" />
        </section>
      </div>
    </CommonLoader>
  </LayoutContent>
</template>
