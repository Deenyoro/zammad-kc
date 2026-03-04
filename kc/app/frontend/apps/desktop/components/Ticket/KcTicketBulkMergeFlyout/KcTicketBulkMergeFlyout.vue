<!-- KC: Bulk merge flyout — merges selected tickets into a parent.
     Uses the FieldTicket autocomplete for parent ticket search and
     calls the KC REST API /api/v1/kc/bulk_merge. -->

<script setup lang="ts">
import gql from 'graphql-tag'
import { computed, ref } from 'vue'

import {
  NotificationTypes,
  useNotifications,
} from '#shared/components/CommonNotifications/index.ts'
import Form from '#shared/components/Form/Form.vue'
import type { FormSubmitData } from '#shared/components/Form/types.ts'
import { useForm } from '#shared/components/Form/useForm.ts'
import { getIdFromGraphQLId } from '#shared/graphql/utils.ts'
import { i18n } from '#shared/i18n.ts'
import { getApolloClient } from '#shared/server/apollo/client.ts'

import CommonLabel from '#shared/components/CommonLabel/CommonLabel.vue'

import CommonButton from '#desktop/components/CommonButton/CommonButton.vue'
import CommonFlyout from '#desktop/components/CommonFlyout/CommonFlyout.vue'
import { closeFlyout } from '#desktop/components/CommonFlyout/useFlyout.ts'
import type { TicketRelationAndRecentListItem } from '#desktop/pages/ticket/components/TicketDetailView/TicketSimpleTable/types.ts'
import { useTargetTicketOptions } from '#desktop/pages/ticket/composables/useTargetTicketOptions.ts'

import { kcApiFetch } from '#shared/composables/useKcApi.ts'

import KcSelectedTicketsList from './KcSelectedTicketsList.vue'

// Inline fragment for reading ticket data from Apollo cache.
// These fields match TicketRelationAndRecentListItem requirements.
const TICKET_CACHE_FRAGMENT = gql`
  fragment KcBulkMergeTicket on Ticket {
    id
    internalId
    number
    title
    createdAt
    stateColorCode
    customer {
      id
      fullname
    }
    organization {
      id
      name
    }
    state {
      id
      name
    }
    group {
      id
      name
    }
  }
`

interface Props {
  ticketIds: ID[]
}

const props = defineProps<Props>()

const emit = defineEmits<{
  success: []
}>()

const { form, formNodeId, updateFieldValues, onChangedField } = useForm()

const {
  formListTargetTicketOptions,
  targetTicketId,
  handleTicketClick,
} = useTargetTicketOptions(onChangedField, updateFieldValues)

const flyoutName = 'kc-tickets-bulk-merge'

// Read selected tickets from Apollo cache (populated by overview query)
const selectedTickets = computed<TicketRelationAndRecentListItem[]>(() => {
  const client = getApolloClient()
  const tickets: TicketRelationAndRecentListItem[] = []

  for (const id of props.ticketIds) {
    const data = client.cache.readFragment<TicketRelationAndRecentListItem>({
      id: client.cache.identify({ __typename: 'Ticket', id }),
      fragment: TICKET_CACHE_FRAGMENT,
    })
    if (data) tickets.push(data)
  }

  return tickets
})

// Raw schema array (not defineFormSchema) — matches upstream pattern for
// passing options to the ticket field type.
const mergeFormSchema = [
  {
    name: 'targetTicketId',
    type: 'ticket',
    label: __('Parent ticket'),
    options: formListTargetTicketOptions,
    clearable: true,
    required: true,
  },
]

interface BulkMergeFormData {
  targetTicketId: string
}

interface BulkMergeResponse {
  success: boolean
  parent_ticket_id: number
  merged_count: number
}

const { notify } = useNotifications()

const submitting = ref(false)

const submitMerge = async (formData: FormSubmitData<BulkMergeFormData>) => {
  submitting.value = true

  try {
    // Convert GraphQL IDs to internal IDs for the REST API
    const childIds = props.ticketIds.map((id) => getIdFromGraphQLId(id))
    const parentId = getIdFromGraphQLId(formData.targetTicketId)

    const result = await kcApiFetch<BulkMergeResponse>('/bulk_merge', {
      method: 'POST',
      body: JSON.stringify({
        ticket_ids: childIds,
        parent_ticket_id: parentId,
      }),
    })

    notify({
      id: 'kc-tickets-merged',
      type: NotificationTypes.Success,
      message: i18n.t('Successfully merged %s ticket(s).', result.merged_count),
    })

    emit('success')
    closeFlyout(flyoutName)
  } catch (error) {
    const message =
      error instanceof Error ? error.message : i18n.t('Merge failed.')

    notify({
      id: 'kc-tickets-merge-error',
      type: NotificationTypes.Error,
      message,
    })
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <CommonFlyout
    :name="flyoutName"
    :header-title="__('Merge tickets')"
    header-icon="merge"
    size="medium"
    no-close-on-action
  >
    <div class="space-y-6">
      <CommonLabel>
        {{
          ticketIds.length === 1
            ? $t('Merge %s ticket into parent:', ticketIds.length)
            : $t('Merge %s tickets into parent:', ticketIds.length)
        }}
      </CommonLabel>

      <Form
        id="form-kc-tickets-bulk-merge"
        ref="form"
        should-autofocus
        :schema="mergeFormSchema"
        @submit="submitMerge($event as FormSubmitData<BulkMergeFormData>)"
      />

      <KcSelectedTicketsList
        :tickets="selectedTickets"
        :selected-ticket-id="targetTicketId"
        @click-ticket="handleTicketClick"
      />
    </div>
    <template #footer="{ close }">
      <div class="flex items-center justify-end gap-4">
        <CommonButton size="large" variant="secondary" @click="close">
          {{ $t('Cancel') }}
        </CommonButton>
        <CommonButton
          type="submit"
          size="large"
          variant="submit"
          :form="formNodeId"
          :disabled="submitting"
        >
          {{ submitting ? $t('Merging...') : $t('Merge') }}
        </CommonButton>
      </div>
    </template>
  </CommonFlyout>
</template>
