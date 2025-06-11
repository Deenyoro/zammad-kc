<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

import { useTouchDevice } from '#shared/composables/useTouchDevice.ts'
import { useTicketChannel } from '#shared/entities/ticket/composables/useTicketChannel.ts'
import { useTicketView } from '#shared/entities/ticket/composables/useTicketView.ts'

import TopBarHeader from '#desktop/pages/ticket/components/TicketDetailView/TicketDetailTopBar/TopBarHeader.vue'
import { useTicketInformation } from '#desktop/pages/ticket/composables/useTicketInformation.ts'

interface Props {
  hideDetails: boolean
}

defineProps<Props>()

const isHovering = defineModel<boolean>('hover', {
  required: false,
})

const { ticket } = useTicketInformation()
const { isTicketAgent, isTicketEditable } = useTicketView(ticket)
const { hasChannelAlert, channelAlert } = useTicketChannel(ticket)

const { isTouchDevice } = useTouchDevice()

const isAgentAndHasPermissionAndHasChannelAlarm = computed(
  () => isTicketAgent.value && isTicketEditable.value && hasChannelAlert.value,
)

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
</script>

<template>
  <div
    class="z-10"
    :tabindex="!isAgentAndHasPermissionAndHasChannelAlarm ? -1 : hideDetails ? 0 : -1"
    v-on="isAgentAndHasPermissionAndHasChannelAlarm ? events : {}"
  >
    <template v-if="isAgentAndHasPermissionAndHasChannelAlarm">
      <TopBarHeader :hide-details="hideDetails" />

      <CommonAlert
        class="rounded-none px-14 md:grid-cols-none md:justify-center"
        :variant="channelAlert?.variant"
      >
        {{ $t(channelAlert?.text, channelAlert?.textPlaceholder) }}
      </CommonAlert>
    </template>
    <TopBarHeader v-else ref="wrapper" :hide-details="hideDetails" v-on="events" />
  </div>
</template>
