<!-- Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed, toRef } from 'vue'

import { NotificationTypes } from '#shared/components/CommonNotifications/types.ts'
import { useNotifications } from '#shared/components/CommonNotifications/useNotifications.ts'
import type { FormRef } from '#shared/components/Form/types.ts'
import { useMacros } from '#shared/entities/macro/composables/useMacros.ts'
import type { MacroById } from '#shared/entities/macro/types.ts'
import type { TicketLiveAppUser } from '#shared/entities/ticket/types.ts'
import { useTicketSharedDraftZoomCreateMutation } from '#shared/entities/ticket-shared-draft-zoom/graphql/mutations/ticketSharedDraftZoomCreate.api.ts'
import { MutationHandler } from '#shared/server/apollo/handler/index.ts'

import CommonButton from '#desktop/components/CommonButton/CommonButton.vue'
import { useDialog } from '#desktop/components/CommonDialog/useDialog.ts'
import type { MenuItem } from '#desktop/components/CommonPopoverMenu/types.ts'
import SplitButton from '#desktop/components/SplitButton/SplitButton.vue'
import TicketScreenBehavior from '#desktop/pages/ticket/components/TicketDetailView/TicketScreenBehavior/TicketScreenBehavior.vue'
import { useTicketSharedDraft } from '#desktop/pages/ticket/composables/useTicketSharedDraft.ts'

import TicketLiveUsers from './TicketLiveUsers.vue'
import TicketSharedDraftZoom from './TicketSharedDraftZoom.vue'

export interface Props {
  dirty: boolean
  disabled: boolean
  isTicketEditable: boolean
  isTicketAgent: boolean
  ticketId: string
  groupId?: string
  form?: FormRef
  hasAvailableDraft?: boolean
  canUseDraft?: boolean
  sharedDraftId?: string | null
  liveUserList: TicketLiveAppUser[]
}

const props = defineProps<Props>()

const groupId = toRef(props, 'groupId')
const isTicketEditable = toRef(props, 'isTicketEditable')

const emit = defineEmits<{
  submit: [MouseEvent]
  discard: [MouseEvent]
  'execute-macro': [MacroById]
}>()

// For now handover ticket editable, flag, maybe later we can move the action menu in an own component.
const { macros } = useMacros(groupId, isTicketEditable)

const { notify } = useNotifications()

const groupLabels = {
  drafts: __('Drafts'),
  macros: __('Macros'),
}

const { mapSharedDraftParams } = useTicketSharedDraft()

const sharedDraftConflictDialog = useDialog({
  name: 'shared-draft-conflict',
  component: () => import('../TicketSharedDraftConflictDialog.vue'),
})

const actionItems = computed(() => {
  const saveAsDraftAction: MenuItem = {
    label: __('Save as draft'),
    groupLabel: groupLabels.drafts,
    icon: 'floppy',
    key: 'save-draft',
    show: () => props.canUseDraft,
    onClick: () => {
      if (props.sharedDraftId) {
        sharedDraftConflictDialog.open({
          sharedDraftId: props.sharedDraftId,
          sharedDraftParams: mapSharedDraftParams(props.ticketId, props.form),
          form: props.form,
        })

        return
      }

      const draftCreateMutation = new MutationHandler(
        useTicketSharedDraftZoomCreateMutation(),
        {
          errorNotificationMessage: __('Draft could not be saved.'),
        },
      )

      draftCreateMutation
        .send({ input: mapSharedDraftParams(props.ticketId, props.form) })
        .then(() => {
          notify({
            id: 'shared-draft-detail-view-created',
            type: NotificationTypes.Success,
            message: __('Shared draft has been created successfully.'),
          })
        })
    },
  }

  if (!macros.value) return [saveAsDraftAction]

  const macroMenu: MenuItem[] = macros.value.map((macro) => ({
    key: macro.id,
    label: macro.name,
    groupLabel: groupLabels.macros,
    onClick: () => emit('execute-macro', macro),
  }))

  return [saveAsDraftAction, ...(groupId.value ? macroMenu : [])]
})
</script>

<template>
  <div class="flex gap-4 ltr:mr-auto rtl:ml-auto">
    <TicketLiveUsers
      v-if="liveUserList?.length"
      :live-user-list="liveUserList"
    />

    <TicketSharedDraftZoom
      v-if="hasAvailableDraft"
      :form="form"
      :shared-draft-id="sharedDraftId"
    />
  </div>

  <template v-if="isTicketEditable">
    <CommonButton
      v-if="dirty"
      size="large"
      variant="danger"
      :disabled="disabled"
      @click="$emit('discard', $event)"
      >{{ $t('Discard your unsaved changes') }}
    </CommonButton>

    <TicketScreenBehavior />

    <SplitButton
      v-if="isTicketAgent"
      size="large"
      variant="submit"
      type="button"
      :disabled="disabled"
      :items="actionItems"
      :addon-label="__('Additional ticket edit actions')"
      @click="$emit('submit', $event)"
    >
      {{ $t('Update') }}
    </SplitButton>

    <CommonButton
      v-else
      size="large"
      variant="submit"
      type="button"
      :disabled="disabled"
      @click="$emit('submit', $event)"
      >{{ $t('Update') }}
    </CommonButton>
  </template>
</template>
