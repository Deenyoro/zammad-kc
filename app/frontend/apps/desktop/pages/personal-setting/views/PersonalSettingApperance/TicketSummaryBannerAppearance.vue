<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { useTicketSummaryBanner } from '#desktop/entities/user/current/composables/useTicketSummaryBanner.ts'

const { showBanner, toggleSummaryBanner, isTicketSummaryFeatureEnabled } =
  useTicketSummaryBanner()
</script>

<template>
  <div v-if="isTicketSummaryFeatureEnabled">
    <CommonLabel tag="h3">
      {{ $t('Ticket Summary') }}
    </CommonLabel>
    <FormKit
      :model-value="showBanner"
      label="Show an info banner in the article list indicating that a summary has been created by %s."
      :label-placeholder="['Zammad Smart Assist']"
      name="toggle-dismiss-ticket-summary-banner"
      type="checkbox"
      :aria-label="
        showBanner
          ? $t('Disable the banner for the ticket summary smart assist')
          : $t('Enable the banner for the ticket summary smart assist')
      "
      @update:model-value="toggleSummaryBanner"
    />
  </div>
</template>
