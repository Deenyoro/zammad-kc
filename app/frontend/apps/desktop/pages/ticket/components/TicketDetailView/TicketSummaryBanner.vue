<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

import CommonTranslateRenderer from '#shared/components/CommonTranslateRenderer/CommonTranslateRenderer.vue'
import { useConfirmation } from '#shared/composables/useConfirmation.ts'
import { getTicketView } from '#shared/entities/ticket/utils/getTicketView.ts'
import { useSessionStore } from '#shared/stores/session.ts'

import CommonButton from '#desktop/components/CommonButton/CommonButton.vue'
import { useTicketSummaryBanner } from '#desktop/entities/user/current/composables/useTicketSummaryBanner.ts'
import { useTicketInformation } from '#desktop/pages/ticket/composables/useTicketInformation.ts'
import { useTicketSidebar } from '#desktop/pages/ticket/composables/useTicketSidebar.ts'

const sidebar = useTicketSidebar()

const { toggleSummaryBanner, showBanner, isTicketSummaryFeatureEnabled } =
  useTicketSummaryBanner()

const { waitForConfirmation } = useConfirmation()

const { ticket } = useTicketInformation()

const isTicketAgent = computed(() =>
  ticket.value ? getTicketView(ticket.value).isTicketAgent : false,
)

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
    v-if="isTicketSummaryFeatureEnabled && isTicketAgent && showBanner"
    class="flex items-center gap-1 rounded-lg border border-(--border-color) px-4 py-3 [--border-color:var(--color-blue-800)]"
  >
    <CommonIcon
      class="flex-shrink-0 text-(--border-color)!"
      size="small"
      name="smart-assist"
    />

    <CommonTranslateRenderer
      class="text-sm text-gray-100 dark:text-neutral-400"
      :source="__('%s has prepared a summary of this ticket.')"
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
      <CommonButton
        :aria-label="$t('Hide ticket summary banner')"
        @click="handleHideSummaryMessage"
        >{{ $t('Hide') }}
      </CommonButton>
      <CommonButton
        size="medium"
        variant="tertiary"
        @click="() => sidebar?.switchSidebar('ticket-summary')"
        >{{ $t('See Summary') }}
      </CommonButton>
    </div>
  </div>
</template>
