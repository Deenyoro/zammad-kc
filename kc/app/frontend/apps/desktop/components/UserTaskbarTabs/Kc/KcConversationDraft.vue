<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<!-- KC: Taskbar tab of a new-conversation draft (RingCentral SMS, FreePBX SMS,
     Teams chat), styled like the ticket create tab. The label names the
     recipient like the legacy UI does ("SMS: +15555550100"): from the live
     form while the draft is open here, from the stored form otherwise (after
     a reload, or for a draft written in the legacy UI). -->

<script setup lang="ts">
import { computed, ref, toRef, watch } from 'vue'

import { useUserTaskbarTab } from '#desktop/composables/useUserTaskbarTab.ts'
import {
  fetchKcDraftState,
  kcConversationDraftByEntity,
  kcDraftTitle,
  type KcDraftState,
} from '#desktop/entities/kc-conversation-draft/drafts.ts'

import type { UserTaskbarTabEntityProps } from '../types.ts'

const props = defineProps<UserTaskbarTabEntityProps>()

const { tabLinkInstance, taskbarTabActive } = useUserTaskbarTab(toRef(props, 'taskbarTab'))

const kind = computed(() => kcConversationDraftByEntity(props.taskbarTab.type))

const storedState = ref<KcDraftState>({})

const liveState = computed(() => props.context?.formValues as KcDraftState | undefined)

// Read again whenever the task changes (updatedAt), unless the open form
//   already tells.
watch(
  () => [props.taskbarTab.tabEntityKey, props.taskbarTab.updatedAt, !!liveState.value] as const,
  async ([tabEntityKey, , live]) => {
    if (live || !props.taskbarTab.taskbarTabId) return

    try {
      const { state } = await fetchKcDraftState(tabEntityKey)
      storedState.value = state || {}
    } catch {
      // Keep the label as it is.
    }
  },
  { immediate: true },
)

const currentViewTitle = computed(() => {
  if (!kind.value) return ''

  return kcDraftTitle(kind.value, liveState.value ?? storedState.value)
})
</script>

<template>
  <CommonLink
    v-if="taskbarTabLink"
    ref="tabLinkInstance"
    v-tooltip="currentViewTitle"
    class="flex grow items-center gap-2 px-2 py-3 group-hover/tab:bg-blue-600 hover:no-underline! group-hover/tab:dark:bg-blue-900"
    :class="{
      ['bg-blue-800! text-white']: taskbarTabActive,
      'group-focus-visible/link:text-white': collapsed,
      'rounded-lg!': !collapsed,
    }"
    :aria-current="isActive ? 'page' : undefined"
    :link="taskbarTabLink"
    internal
  >
    <CommonIcon
      class="shrink-0 text-stone-200 dark:text-neutral-500"
      :class="{
        'text-white!': taskbarTabActive,
      }"
      name="pencil"
      size="tiny"
      decorative
    />

    <CommonLabel
      class="block! truncate text-gray-300 group-hover/tab:text-white dark:text-neutral-400"
      :class="{
        'text-white!': taskbarTabActive,
      }"
    >
      {{ currentViewTitle }}
    </CommonLabel>
  </CommonLink>
</template>
