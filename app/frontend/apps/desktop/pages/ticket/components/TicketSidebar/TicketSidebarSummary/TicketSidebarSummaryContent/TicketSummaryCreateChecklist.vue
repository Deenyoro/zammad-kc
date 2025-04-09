<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

import {
  NotificationTypes,
  useNotifications,
} from '#shared/components/CommonNotifications/index.ts'
import { MutationHandler } from '#shared/server/apollo/handler/index.ts'

import CommonButton from '#desktop/components/CommonButton/CommonButton.vue'
import TicketSummaryItem from '#desktop/pages/ticket/components/TicketSidebar/TicketSidebarSummary/TicketSidebarSummaryContent/TicketSummaryItem.vue'
import { useTicketInformation } from '#desktop/pages/ticket/composables/useTicketInformation.ts'
import { useTicketSidebar } from '#desktop/pages/ticket/composables/useTicketSidebar.ts'
import { useTicketChecklistAddMutation } from '#desktop/pages/ticket/graphql/mutations/ticketChecklistAdd.api.ts'
import { useTicketChecklistItemsAddMutation } from '#desktop/pages/ticket/graphql/mutations/ticketChecklistItemsAdd.api.ts'
import { useTicketChecklistItemUpsertMutation } from '#desktop/pages/ticket/graphql/mutations/ticketChecklistItemUpsert.api.ts'

interface Props {
  summary: string[]
  label: string
}

const props = defineProps<Props>()

const { ticket } = useTicketInformation()

const ticketChecklist = computed(() => ticket.value?.checklist)

const sidebar = useTicketSidebar()

const { notify } = useNotifications()

const addNewChecklistHandler = new MutationHandler(
  useTicketChecklistAddMutation(),
)

const ticketChecklistUpsertMutation = new MutationHandler(
  useTicketChecklistItemUpsertMutation(),
)

const createNewChecklist = async () => {
  const response = await addNewChecklistHandler.send({
    ticketId: ticket.value!.id,
  })

  return response?.ticketChecklistAdd?.checklist
}

const createNewChecklistItem = async (text: string) => {
  const checklist = ticketChecklist.value || (await createNewChecklist())

  if (!checklist) return

  ticketChecklistUpsertMutation
    .send({
      checklistId: checklist.id,
      input: { text, checked: false },
    })
    .then(() =>
      notify({
        id: 'checklist-item-create',
        type: NotificationTypes.Success,
        message: __('Checklist item successfully added.'),
      }),
    )
    .catch(() =>
      notify({
        id: 'checklist-item-create-error',
        type: NotificationTypes.Error,
        message: __('Failed to add new checklist item.'),
      }),
    )
}

const ticketChecklistItemsAddHandler = new MutationHandler(
  useTicketChecklistItemsAddMutation(),
)

const convertAllToChecklistItems = async () => {
  const checklist = ticketChecklist.value || (await createNewChecklist())
  if (!checklist) return

  const input = props.summary.map((text) => ({ text, checked: false }))

  return ticketChecklistItemsAddHandler
    .send({ checklistId: checklist.id, input })
    .then(() => sidebar.switchSidebar('checklist'))
    .catch(() =>
      notify({
        id: 'checklist-item-create-error',
        type: NotificationTypes.Error,
        message: __('Failed to add new checklist items.'),
      }),
    )
}
</script>

<template>
  <TicketSummaryItem :label="label" :summary="summary" variant="ai">
    <template #item-trailing="{ content }">
      <CommonButton
        prefix-icon="check2-circle"
        class="col-span-2"
        :aria-label="$t('Add as checklist item')"
        @click="createNewChecklistItem(content)"
      >
        {{ $t('Add') }}
      </CommonButton>
    </template>

    <template #trailing>
      <CommonButton
        prefix-icon="check2-all-circle"
        class="mt-0.5 self-end"
        @click="convertAllToChecklistItems"
        >{{ $t('Add all to checklist') }}</CommonButton
      >
    </template>
  </TicketSummaryItem>
</template>
