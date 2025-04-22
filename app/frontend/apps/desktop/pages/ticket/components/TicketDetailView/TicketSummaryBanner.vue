<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed, ref } from 'vue'

import CommonTranslateRenderer from '#shared/components/CommonTranslateRenderer/CommonTranslateRenderer.vue'
import { useConfirmation } from '#shared/composables/useConfirmation.ts'
import { getTicketView } from '#shared/entities/ticket/utils/getTicketView.ts'
import { useSessionStore } from '#shared/stores/session.ts'
import emitter from '#shared/utils/emitter.ts'

import CommonButton from '#desktop/components/CommonButton/CommonButton.vue'
import { useTicketSummaryBanner } from '#desktop/entities/user/current/composables/useTicketSummaryBanner.ts'
import { useTicketInformation } from '#desktop/pages/ticket/composables/useTicketInformation.ts'
import { useTicketSidebar } from '#desktop/pages/ticket/composables/useTicketSidebar.ts'
import { useTicketSummarySeen } from '#desktop/pages/ticket/composables/useTicketSummarySeen.ts'

const sidebar = useTicketSidebar()

const {
  toggleSummaryBanner,
  hideBannerFromUserPreference,
  isTicketSummaryFeatureEnabled,
} = useTicketSummaryBanner()

const {
  currentSummaryFingerprint,
  isCurrentTicketSummaryRead,
  isTicketStateMerged,
  isTicketSummarySidebarActive,
  storeFingerprint,
} = useTicketSummarySeen()

const { waitForConfirmation } = useConfirmation()

const { ticket } = useTicketInformation()

const isTicketAgent = computed(() =>
  ticket.value ? getTicketView(ticket.value).isTicketAgent : false,
)

const isSummaryGenerating = ref(false)

emitter.on('ticket-summary-generating', (isGenerating) => {
  isSummaryGenerating.value = isGenerating
})

const showBanner = computed(
  () =>
    isTicketSummaryFeatureEnabled.value &&
    isTicketAgent.value &&
    hideBannerFromUserPreference.value &&
    !isTicketStateMerged.value &&
    ((isSummaryGenerating.value && !isTicketSummarySidebarActive.value) ||
      !isCurrentTicketSummaryRead.value),
)

const seeSummary = () => {
  if (!isTicketSummarySidebarActive.value) {
    sidebar?.switchSidebar('ticket-summary')
    return
  }

  storeFingerprint(currentSummaryFingerprint.value)
}

const { userId } = useSessionStore()

const handleHideSummaryMessage = async () => {
  const confirmed = await waitForConfirmation(
    __('You can re-enable it anytime in Profile Settings > Appearance.'),
    {
      headerTitle: __('Hide Smart Assist Summary Banner?'),
      buttonLabel: __('Yes, hide it'),
      fullscreen: true,
    },
    `ticket-summary-banner-${userId}`,
  )
  if (confirmed) {
    toggleSummaryBanner(false)
  }
}
</script>

<template>
  <div
    v-if="showBanner"
    data-test-id="ticket-summary-banner"
    class="ai-stripe relative flex items-center gap-1 rounded-lg px-4 py-3 before:absolute before:top-0 before:right-0 before:left-0"
  >
    <CommonIcon
      class="shrink-0 text-blue-800"
      size="small"
      name="smart-assist"
    />

    <CommonTranslateRenderer
      class="text-sm text-gray-100 dark:text-neutral-400"
      :source="
        isSummaryGenerating
          ? __('%s is preparing summary…')
          : __('%s ticket summary has been generated.')
      "
      :placeholders="[
        {
          type: 'label',
          props: {
            class: 'text-black! dark:text-white!',
          },
          content: 'Zammad Smart Assist',
        },
      ]"
    />

    <div class="flex items-center gap-4 ltr:ml-auto rtl:mr-auto">
      <CommonButton size="small" @click="seeSummary">
        {{ $t('See Summary') }}
      </CommonButton>
      <CommonButton
        variant="neutral"
        :aria-label="$t('Hide ticket summary banner')"
        icon="x-lg"
        @click="handleHideSummaryMessage"
      />
    </div>
  </div>
</template>
