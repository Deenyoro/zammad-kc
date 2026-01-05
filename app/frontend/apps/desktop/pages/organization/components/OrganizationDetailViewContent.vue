<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed, useTemplateRef } from 'vue'

import ObjectAttributes from '#shared/components/ObjectAttributes/ObjectAttributes.vue'
import { useOrganizationDetail } from '#shared/entities/organization/composables/useOrganizationDetail.ts'
import { useOrganizationEntity } from '#shared/entities/organization/composables/useOrganizationEntity.ts'
import { useOrganizationNoteUpdateMutation } from '#shared/entities/organization/graphql/mutations/noteUpdate.api.ts'
import { convertToGraphQLId } from '#shared/graphql/utils.ts'
import { GraphQLErrorTypes } from '#shared/types/error.ts'

import CommonLoader from '#desktop/components/CommonLoader/CommonLoader.vue'
import LayoutContent from '#desktop/components/layout/LayoutContent.vue'
import { usePage } from '#desktop/composables/usePage.ts'
import { useScrollPosition } from '#desktop/composables/useScrollPosition.ts'

import OrganizationDetailTopBar from './OrganizationDetailTopBar.vue'

interface Props {
  internalId: string
}

const props = defineProps<Props>()

const organizationId = computed(() => convertToGraphQLId('Organization', props.internalId))

const { organization, objectAttributes } = useOrganizationDetail(
  organizationId,
  4,
  100,
  // NB: Silence toast notifications for particular errors, these will be handled by the layout taskbar tab component.
  (errorHandler) =>
    errorHandler.type !== GraphQLErrorTypes.Forbidden &&
    errorHandler.type !== GraphQLErrorTypes.RecordNotFound,
  'cache-first',
)

const { organizationDisplayName } = useOrganizationEntity(organization)

usePage({
  metaTitle: organizationDisplayName,
})

const contentContainerElement = useTemplateRef('content-container')

useScrollPosition(contentContainerElement)
</script>

<template>
  <LayoutContent
    name="organization-detail"
    no-padding
    background-variant="primary"
    content-alignment="center"
    no-scrollable
  >
    <CommonLoader class="mt-8" :loading="!organization">
      <div ref="content-container" class="h-full w-full overflow-y-auto">
        <OrganizationDetailTopBar
          :organization="organization"
          :organization-display-name="organizationDisplayName"
          :content-container-element="contentContainerElement"
        />
        <section class="mx-auto w-full max-w-5xl grid grid-cols-2 gap-6 p-6">
          <div class="self-start flex flex-col gap-6">
            <!-- TODO: Members -->
            <ObjectAttributes
              :attributes="objectAttributes"
              :object="organization"
              :skip-attributes="['name']"
              :inline-editable="{ note: useOrganizationNoteUpdateMutation }"
            />
          </div>

          <!-- TODO: Organization tickets -->

          <!-- TODO: Ticket frequency chart -->
        </section>
      </div>
    </CommonLoader>
  </LayoutContent>
</template>
