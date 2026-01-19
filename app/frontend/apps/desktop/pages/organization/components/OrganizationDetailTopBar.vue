<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed, ref, toRef, type Ref } from 'vue'
import { useRouter } from 'vue-router'

import { useCopyToClipboard } from '#shared/composables/useCopyToClipboard.ts'
import { useTouchDevice } from '#shared/composables/useTouchDevice.ts'
import type { Organization } from '#shared/graphql/types.ts'
import { useApplicationStore } from '#shared/stores/application.ts'
import { useSessionStore } from '#shared/stores/session.ts'

import CommonActionMenu from '#desktop/components/CommonActionMenu/CommonActionMenu.vue'
import CommonBreadcrumb from '#desktop/components/CommonBreadcrumb/CommonBreadcrumb.vue'
import CommonButton from '#desktop/components/CommonButton/CommonButton.vue'
import OrganizationInfo from '#desktop/components/Organization/OrganizationInfo.vue'
import { useElementScroll } from '#desktop/composables/useElementScroll.ts'

import { initializeActionPlugins } from './OrganizationDetailTopBar/actions/index.ts'

interface Props {
  organization: Organization
  organizationDisplayName: string
  contentContainerElement: HTMLElement | null
}

const props = defineProps<Props>()

const breadcrumbItems = computed(() => [
  // TODO: Adjust breadcrumbs when the navigational mechanism is in place.
  {
    label: __('Organization'),
  },
  {
    label: props.organizationDisplayName,
    noOptionLabelTranslation: true,
  },
])

const { copyToClipboard } = useCopyToClipboard()

const config = toRef(useApplicationStore(), 'config')

const copyOrganizationDisplayNameToClipboard = () => {
  copyToClipboard([
    new ClipboardItem({
      'text/plain': props.organizationDisplayName,
      'text/html': `<a href="${config.value.http_type}://${config.value.fqdn}/desktop/organizations/${props.organization.internalId}">${props.organizationDisplayName}</a>`,
    }),
  ])
}

const { y } = useElementScroll(toRef(props, 'contentContainerElement') as Ref<HTMLDivElement>)

const isHovering = ref(false)

const { isTouchDevice } = useTouchDevice()

const events = computed(() => {
  if (isTouchDevice.value)
    return {
      touchstart() {
        isHovering.value = true
      },
      touchend() {
        isHovering.value = false
      },
    }

  return {
    mouseenter() {
      isHovering.value = true
    },
    mouseleave() {
      isHovering.value = false
    },
  }
})

const { topLevelActions, secondLevelActions } = initializeActionPlugins()

const { hasPermission } = useSessionStore()

const allowedTopLevelActions = computed(() =>
  topLevelActions.filter(
    (item) =>
      (item.permission ? hasPermission(item.permission) : true) &&
      (item.show ? item.show(props.organization) : true),
  ),
)

const router = useRouter()
</script>

<template>
  <header
    class="absolute top-0 left-0 right-0 z-30 w-full h-17 border-b border-neutral-100 bg-neutral-50 p-3 dark:border-gray-900 dark:bg-gray-500"
    :style="{
      transform: `translateY(${y - (137 + 70) > 0 ? 0 : y - (137 + 70)}px)`,
    }"
    aria-hidden="true"
    v-on="events"
  >
    <div class="flex mx-auto w-full max-w-266">
      <OrganizationInfo :organization="organization" size="small" title-size="large" no-link />
    </div>
  </header>
  <header
    data-test-id="organization-detail-top-bar"
    class="sticky z-30 h-34 border-b border-neutral-100 bg-neutral-50 p-3 dark:border-gray-900 dark:bg-gray-500"
    :class="{
      'transition-[top]': isHovering,
    }"
    :style="{
      top: isHovering ? '0px' : y < 137 ? `-${y}px` : '-137px',
    }"
    v-on="events"
  >
    <CommonBreadcrumb :items="breadcrumbItems" size="small" emphasize-last-item>
      <template #trailing>
        <CommonButton
          v-if="organizationDisplayName"
          v-tooltip="$t('Copy organization display name')"
          variant="secondary"
          icon="files"
          size="small"
          class="ms-1"
          @click="copyOrganizationDisplayNameToClipboard"
        />
      </template>
    </CommonBreadcrumb>
    <div class="flex mx-auto mt-3 pe-17 w-full max-w-278 h-21">
      <OrganizationInfo
        :organization="organization"
        size="normal"
        title-size="xl"
        title-class="font-medium"
        no-link
      >
        <template #actions>
          <div role="menubar" class="rtl:mr-auto ltr:ml-auto flex items-center gap-1.5">
            <CommonButton
              v-for="action in allowedTopLevelActions"
              :key="action.key"
              role="menuitem"
              :prefix-icon="action.icon"
              @click="action?.onClick?.(organization, router)"
            >
              {{ $t(action.label) }}
            </CommonButton>
            <CommonActionMenu
              button-size="large"
              :entity="organization"
              role="menuitem"
              no-single-action-mode
              :actions="secondLevelActions"
            />
          </div>
        </template>
      </OrganizationInfo>
    </div>
  </header>
</template>
