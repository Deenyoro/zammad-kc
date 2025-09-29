<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { storeToRefs } from 'pinia'
import { computed } from 'vue'

import { getTicketNumberWithHook } from '#shared/entities/ticket/composables/getTicketNumber.ts'
import { useApplicationStore } from '#shared/stores/application.ts'

import CommonPopoverWithTrigger from '#desktop/components/CommonPopover/CommonPopoverWithTrigger.vue'
import CommonPopoverMenu from '#desktop/components/CommonPopoverMenu/CommonPopoverMenu.vue'
import type { MenuItem } from '#desktop/components/CommonPopoverMenu/types.ts'
import CommonTicketLabel from '#desktop/components/CommonTicketLabel/CommonTicketLabel.vue'
import ChecklistBadge from '#desktop/pages/ticket/components/TicketDetailView/TicketDetailTopBar/TopBarHeader/TicketInformation/TicketInformationBadgeList/ChecklistBadge.vue'
import type {
  ReferencingTicket,
  TicketReferenceMenuItem,
} from '#desktop/pages/ticket/components/TicketDetailView/TicketDetailTopBar/TopBarHeader/TicketInformation/TicketInformationBadgeList/types.ts'

const { config } = storeToRefs(useApplicationStore())

interface Props {
  referencingTickets: ReferencingTicket[]
}

const props = defineProps<Props>()

const ticketReferenceMenuItems = computed<Array<MenuItem> | undefined>(() =>
  props.referencingTickets?.map((ticket, index) => ({
    ticket,
    key: `popover-checklist-title-item-${index}`,
  })),
)

const referencingTicketsCount = computed(() => props.referencingTickets.length)

const menuItemKeys = computed(() => ticketReferenceMenuItems.value?.map((item) => item.key))
</script>

<template>
  <CommonPopoverWithTrigger
    class="rounded-md outline-offset-1 focus-visible:outline-2"
    placement="arrowEnd"
    orientation="bottom"
    trigger-link-active-class="outline-blue-800! outline-2!"
    :aria-label="
      referencingTicketsCount === 1 ? $t('Show tracking ticket') : $t('Show tracking tickets')
    "
    no-min-width
    no-full-width
  >
    <template #popover-content="{ popover, close }">
      <CommonPopoverMenu
        ref="popoverMenu"
        :header-label="$t('Tracked as checklist item in')"
        :items="ticketReferenceMenuItems"
        :popover="popover"
      >
        <template v-for="key in menuItemKeys" :key="key" #[`item-${key}`]="item">
          <CommonTicketLabel
            v-tooltip="
              `${getTicketNumberWithHook(
                config.ticket_hook,
                (item as unknown as TicketReferenceMenuItem).ticket.number,
              )} - ${(item as unknown as TicketReferenceMenuItem).ticket.title}`
            "
            class="group p-2.5 focus-visible:outline-transparent"
            :classes="{
              indicator: 'group-focus:text-white',
              label: 'group-focus:text-white',
            }"
            :ticket="(item as unknown as TicketReferenceMenuItem).ticket"
            no-wrap
            @click="close"
          />
        </template>
      </CommonPopoverMenu>
    </template>

    <ChecklistBadge class="cursor-pointer h-7" tag="div">
      <CommonLabel size="small" class="text-black! dark:text-white!">
        {{
          referencingTicketsCount === 1
            ? getTicketNumberWithHook(config.ticket_hook, referencingTickets[0].number as string)
            : $t('%s tickets', referencingTicketsCount)
        }}
      </CommonLabel>
    </ChecklistBadge>
  </CommonPopoverWithTrigger>
</template>
