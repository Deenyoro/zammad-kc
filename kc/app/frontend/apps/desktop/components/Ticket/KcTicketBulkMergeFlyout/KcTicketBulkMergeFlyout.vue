<!-- KC: Bulk merge flyout — merges selected tickets into a parent.
     Uses the FieldTicket autocomplete for parent ticket search and
     calls the KC REST API /api/v1/kc/bulk_merge. -->

<script setup lang="ts">
import { computed, ref } from 'vue'

import {
  NotificationTypes,
  useNotifications,
} from '#shared/components/CommonNotifications/index.ts'
import Form from '#shared/components/Form/Form.vue'
import type { FormSubmitData } from '#shared/components/Form/types.ts'
import { useForm } from '#shared/components/Form/useForm.ts'
import { defineFormSchema } from '#shared/form/defineFormSchema.ts'
import { getIdFromGraphQLId } from '#shared/graphql/utils.ts'
import { i18n } from '#shared/i18n.ts'

import CommonButton from '#desktop/components/CommonButton/CommonButton.vue'
import CommonFlyout from '#desktop/components/CommonFlyout/CommonFlyout.vue'

import { closeFlyout } from '#desktop/components/CommonFlyout/useFlyout.ts'

import { kcApiFetch } from '#shared/composables/useKcApi.ts'

interface Props {
  ticketIds: ID[]
}

const props = defineProps<Props>()

const emit = defineEmits<{
  success: []
}>()

const { form, formNodeId } = useForm()

const flyoutName = 'kc-tickets-bulk-merge'

const formSchema = defineFormSchema([
  {
    isLayout: true,
    component: 'FormGroup',
    children: [
      {
        isLayout: true,
        component: 'CommonLabel',
        children: {
          if: '$ticketIdsCount === 1',
          then: '$t("Merge %s ticket into parent:", $ticketIdsCount)',
          else: '$t("Merge %s tickets into parent:", $ticketIdsCount)',
        },
      },
      {
        name: 'parent_ticket_id',
        type: 'ticket',
        label: __('Parent ticket'),
        required: true,
        props: {
          clearable: true,
        },
      },
    ],
  },
])

interface BulkMergeFormData {
  parent_ticket_id: string
}

interface BulkMergeResponse {
  success: boolean
  parent_ticket_id: number
  merged_count: number
}

const { notify } = useNotifications()

const submitting = ref(false)

const ticketIdsCount = computed(() => props.ticketIds.length)

const schemaData = computed(() => ({
  ticketIdsCount: ticketIdsCount.value,
}))

const submitMerge = async (formData: FormSubmitData<BulkMergeFormData>) => {
  submitting.value = true

  try {
    // Convert GraphQL IDs to internal IDs for the REST API
    const childIds = props.ticketIds.map((id) => getIdFromGraphQLId(id))
    const parentId = getIdFromGraphQLId(formData.parent_ticket_id)

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
    <Form
      id="form-kc-tickets-bulk-merge"
      ref="form"
      should-autofocus
      :schema="formSchema"
      :schema-data="schemaData"
      @submit="submitMerge($event as FormSubmitData<BulkMergeFormData>)"
    />
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
