// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// KC: Keeps the form of a new-conversation screen in its taskbar task, the
// way the legacy UI does (kc_conversation_draft.coffee):
//
//   - restores the stored form when the screen opens (after a reload, or for a
//     draft started in the legacy UI),
//   - stores the form shortly after every change, and right away when the tab
//     is left - with the legacy field names, so the legacy UI restores it too,
//   - takes over a form changed elsewhere (the other UI, another window),
//   - reports whether something was typed, which asks before closing the tab,
//   - closes the tab once the conversation has been created.
//
// Needs to run below LayoutTaskbarTabContent (useTaskbarTab).

import { onBeforeUnmount, onDeactivated, ref, watch } from 'vue'

import type { FormValues } from '#shared/components/Form/types.ts'
import SubscriptionHandler from '#shared/server/apollo/handler/SubscriptionHandler.ts'

import { useTaskbarTab } from '#desktop/entities/user/current/composables/useTaskbarTab.ts'
import { useTaskbarTabContext } from '#desktop/entities/user/current/composables/useTaskbarTabContext.ts'
import { useUserCurrentTaskbarItemStateUpdatesSubscription } from '#desktop/entities/user/current/graphql/subscriptions/userCurrentTaskbarItemStateUpdates.api.ts'

import { fetchKcDraftState, type KcConversationDraftKind, type KcDraftState } from './drafts.ts'

interface KcConversationDraftOptions<T extends KcDraftState> {
  kind: KcConversationDraftKind
  // Current form values, with the field names of the legacy UI.
  collect: () => T
  // Writes stored values back into the form.
  apply: (state: KcDraftState) => void
}

// Same delay as the legacy UI.
const SAVE_DELAY = 250

// How many own saves are remembered to recognize their echo (see below).
const OWN_STATES_KEPT = 20

const isEmptyState = (state?: KcDraftState | null) => !state || Object.keys(state).length === 0

export const useKcConversationDraft = <T extends KcDraftState>({
  kind,
  collect,
  apply,
}: KcConversationDraftOptions<T>) => {
  // Nothing is stored before the stored form has been read - an empty form
  //   would overwrite it.
  const restored = ref(false)

  const tabContext = useTaskbarTabContext(() => {
    const state = collect()

    return {
      formValues: state as FormValues,
      formIsDirty: kind.hasContent(state),
    }
  }, restored)

  const {
    currentTaskbarTab,
    currentTaskbarEntityKey,
    currentTaskbarTabId,
    currentTaskbarTabUpdate,
    currentTaskbarTabDelete,
  } = useTaskbarTab(tabContext)

  // The stored form as far as this window knows, serialized. Undefined while
  //   nothing is stored: an untouched draft stores nothing, like in the legacy
  //   UI, since any stored form marks the task as changed for good.
  let storedState: string | undefined

  // The forms this window stored itself. Each save is reported back as a state
  //   change, and the form read then may already be outdated by a later save -
  //   neither may be applied over what is being typed.
  const ownStates: string[] = []

  let closed = false
  let saveTimer: ReturnType<typeof setTimeout> | undefined

  const cancelSave = () => {
    if (!saveTimer) return

    clearTimeout(saveTimer)
    saveTimer = undefined
  }

  const save = () => {
    cancelSave()

    if (closed || !restored.value) return

    const taskbarTab = currentTaskbarTab.value
    if (!taskbarTab || !currentTaskbarTabId.value) return

    const state = collect()
    const serialized = JSON.stringify(state)

    if (serialized === storedState) return
    if (storedState === undefined && !kind.hasContent(state)) return

    storedState = serialized
    ownStates.push(serialized)
    if (ownStates.length > OWN_STATES_KEPT) ownStates.shift()

    currentTaskbarTabUpdate({ ...taskbarTab, dirty: kind.hasContent(state) }, state)
  }

  const scheduleSave = () => {
    cancelSave()
    saveTimer = setTimeout(save, SAVE_DELAY)
  }

  const applyStoredState = (state: KcDraftState) => {
    apply(state)
    storedState = JSON.stringify(collect())
  }

  const restore = async () => {
    try {
      if (!currentTaskbarEntityKey) return

      const { state } = await fetchKcDraftState(currentTaskbarEntityKey)
      if (closed || isEmptyState(state)) return

      applyStoredState(state)
    } catch {
      // A draft that cannot be read starts empty.
    } finally {
      restored.value = true
    }
  }

  restore()

  watch(
    () => (restored.value ? JSON.stringify(collect()) : undefined),
    (serialized) => {
      if (serialized !== undefined) scheduleSave()
    },
  )

  // The tab is created while the screen opens - what was typed before is
  //   stored once it exists.
  watch(currentTaskbarTabId, (taskbarTabId) => {
    if (taskbarTabId) scheduleSave()
  })

  const stateUpdates = new SubscriptionHandler(
    useUserCurrentTaskbarItemStateUpdatesSubscription(
      () => ({ taskbarItemId: currentTaskbarTabId.value! }),
      () => ({ enabled: !!currentTaskbarTabId.value }),
    ),
  )

  stateUpdates.onSubscribed().then(() => {
    stateUpdates.onResult(async () => {
      if (closed || !restored.value || !currentTaskbarEntityKey) return

      try {
        const { state } = await fetchKcDraftState(currentTaskbarEntityKey)
        if (closed || isEmptyState(state)) return

        const serialized = JSON.stringify(state)
        if (ownStates.includes(serialized)) return
        if (serialized === JSON.stringify(collect())) return

        cancelSave()
        applyStoredState(state)
      } catch {
        // Keep the form as it is.
      }
    })
  })

  // Leaving the tab: store what was typed right before.
  onDeactivated(save)
  onBeforeUnmount(save)

  // The conversation has been created: the draft is done. Called after
  //   navigating away, like the ticket create screen does.
  const closeDraft = () => {
    closed = true
    cancelSave()
    currentTaskbarTabDelete()
  }

  return {
    currentTaskbarEntityKey,
    restored,
    closeDraft,
  }
}
