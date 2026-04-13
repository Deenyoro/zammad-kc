// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { useEventListener, useTimeoutFn } from '@vueuse/core'
import { storeToRefs } from 'pinia'
import { ref, toRef } from 'vue'

import { NotificationTypes } from '#shared/components/CommonNotifications/types.ts'
import { useNotifications } from '#shared/components/CommonNotifications/useNotifications.ts'
import {
  EnumBulkUpdateStatusStatus,
  type TicketBulkPerformInput,
  type TicketBulkSelectorInput,
} from '#shared/graphql/types.ts'
import MutationHandler from '#shared/server/apollo/handler/MutationHandler.ts'
import emitter from '#shared/utils/emitter.ts'

import { useTicketUpdateBulkMutation } from '#desktop/entities/ticket/graphql/mutations/updateBulk.api.ts'
import { useTicketBulkUpdateStore } from '#desktop/entities/user/current/stores/ticketBulkUpdate.ts'

import type { BulkData, DragAndDropBulkEntityType, DragAndDropBulkOptions } from './types'

const LONG_PRESS_DURATION = 200
const MOVE_THRESHOLD_PX = 5

export const useDragAndDropBulk = ({
  checkedTicketIds,
  bulkContext,
  bulkCount,
}: DragAndDropBulkOptions) => {
  const bulkUpdateStore = useTicketBulkUpdateStore()
  const isBulkTaskRunning = toRef(useTicketBulkUpdateStore(), 'isRunning')
  const { requestBulkConfirmation, setTicketBulkUpdateStatus } = bulkUpdateStore
  const { confirmationPending, isRunning } = storeToRefs(bulkUpdateStore)

  const isActive = ref(false)
  const longPressedItemId = ref<ID | null>(null)
  const pendingItemId = ref<ID | null>(null)
  const cursorPosition = ref<{ x: number; y: number }>({ x: 0, y: 0 })

  // Track both conditions: long press elapsed AND pointer moved enough.
  const longPressElapsed = ref(false)
  const hasMovedEnough = ref(false)
  const startPosition = ref<{ x: number; y: number } | null>(null)

  const getItemIdFromEvent = (event: PointerEvent): ID | null => {
    const row = (event.target as HTMLElement).closest<HTMLElement>('[data-item-id]')

    return row?.dataset.itemId ?? null
  }

  const activate = () => {
    if (isBulkTaskRunning.value) return
    if (isActive.value) return

    const itemId = pendingItemId.value

    longPressedItemId.value = itemId && !checkedTicketIds.value.has(itemId) ? itemId : null

    if (longPressedItemId.value) {
      checkedTicketIds.value.add(longPressedItemId.value)
    }

    if (checkedTicketIds.value.size === 0) return

    emitter.emit('close-popover')
    isActive.value = true
  }

  const tryActivate = () => {
    if (!longPressElapsed.value || !hasMovedEnough.value) return

    activate()
  }

  const { start: startLongPress, stop: stopLongPress } = useTimeoutFn(
    () => {
      longPressElapsed.value = true
      tryActivate()
    },
    LONG_PRESS_DURATION,
    { immediate: false },
  )

  const resetState = () => {
    stopLongPress()
    pendingItemId.value = null
    longPressElapsed.value = false
    hasMovedEnough.value = false
    startPosition.value = null
  }

  const cancelDragAndDrop = () => {
    if (longPressedItemId.value) {
      checkedTicketIds.value.delete(longPressedItemId.value)
    }

    longPressedItemId.value = null
    isActive.value = false
    resetState()
  }

  const finishDragAndDrop = () => {
    longPressedItemId.value = null
    isActive.value = false
    checkedTicketIds.value.clear()

    resetState()
  }

  const { notify } = useNotifications()
  const updateBulkMutation = new MutationHandler(useTicketUpdateBulkMutation())

  const buildSelector = (): TicketBulkSelectorInput => {
    const context = bulkContext.value
    const count = bulkCount.value

    if (count && context) {
      if ('overviewId' in context && context.overviewId) return { overviewId: context.overviewId }
      if ('searchQuery' in context && context.searchQuery)
        return { searchQuery: context.searchQuery }
    }

    return { entityIds: Array.from(checkedTicketIds.value) }
  }

  const extractDataFromNode = (node: HTMLElement) => {
    const targetNode = node.closest<HTMLElement>('[data-type][id]')

    if (!targetNode) return null

    return {
      type: targetNode.dataset.type as Required<DragAndDropBulkEntityType>,
      id: targetNode.id as ID,
    }
  }

  const buildPerformInput = (data: BulkData): TicketBulkPerformInput => {
    switch (data.type) {
      case 'macro':
        return { macroId: data.id }
      // case 'owner': // :TODO
      //   return { input: { ownerId: data.id } }
      default:
        throw new Error(`Unknown drop target type: ${data.type}`)
    }
  }

  const executeBulkUpdate = async (data: BulkData) => {
    if (isRunning.value) return false

    const result = await updateBulkMutation.send({
      selector: buildSelector(),
      perform: buildPerformInput(data),
    })

    if (result) {
      const total = result.ticketUpdateBulk?.total ?? checkedTicketIds.value.size

      if (result?.ticketUpdateBulk?.async) {
        setTicketBulkUpdateStatus({
          status: EnumBulkUpdateStatusStatus.Pending,
          processedCount: 0,
          total,
        })

        return
      }

      const failedCount = result.ticketUpdateBulk?.failedCount ?? 0
      const invalidTicketIds = result.ticketUpdateBulk?.invalidTicketIds ?? []
      const invalidTicketCount = invalidTicketIds.length

      // In case there are invalid tickets, show alert messages and allow retry.
      if (failedCount) {
        // Only if some tickets were processed successfully.
        if (total - failedCount > 0)
          notify({
            id: 'ticket-bulk-update-succeeded',
            type: NotificationTypes.Success,
            message: __('Bulk action successful for %s ticket(s).'),
            messagePlaceholder: [(total - failedCount).toString()],
            durationMS: 5000,
          })

        notify({
          id: 'bulk-update-failed',
          type: NotificationTypes.Error,
          message: __('Bulk action failed for %s ticket(s).'),
          messagePlaceholder: [invalidTicketCount.toString()],
          durationMS: 5000,
        })
      } else {
        notify({
          id: 'ticket-bulk-update-succeeded',
          type: NotificationTypes.Success,
          message: __('Bulk action successful for %s ticket(s).'),
          messagePlaceholder: [total.toString()],
        })
      }
    }
  }

  useEventListener(document, 'pointerdown', (event: PointerEvent) => {
    if (event.button !== 0) return // Only respond to primary button.

    const itemId = getItemIdFromEvent(event)

    if (!itemId) return

    pendingItemId.value = itemId
    startPosition.value = { x: event.clientX, y: event.clientY }
    startLongPress()
  })

  useEventListener(document, 'pointermove', (event: PointerEvent) => {
    if (isActive.value) {
      cursorPosition.value = { x: event.clientX, y: event.clientY }
    }

    if (!pendingItemId.value || !startPosition.value) return
    if (hasMovedEnough.value) return // Already passed the threshold.

    const dx = event.clientX - startPosition.value.x
    const dy = event.clientY - startPosition.value.y

    if (dx * dx + dy * dy < MOVE_THRESHOLD_PX * MOVE_THRESHOLD_PX) return

    hasMovedEnough.value = true
    tryActivate()
  })

  useEventListener(document, 'pointerup', async (event) => {
    // Ignore pointer events while waiting for the user to confirm/cancel.
    if (confirmationPending.value) return

    if (!isActive.value) return resetState()

    const data = extractDataFromNode(event.target as HTMLElement)

    if (!data) return cancelDragAndDrop()

    const confirmed = await requestBulkConfirmation(checkedTicketIds.value.size, data.type)

    if (!confirmed) return cancelDragAndDrop()

    executeBulkUpdate(data as BulkData)

    finishDragAndDrop()
  })

  useEventListener(document, 'dragstart', (event: DragEvent) => {
    if (!pendingItemId.value && !isActive.value) return
    if (!(event.target instanceof HTMLElement)) return

    if (event.target.closest('table [data-item-id]')) event.preventDefault()
  })

  // Cancel if pointer leaves the window or the page loses focus.
  useEventListener(document, 'pointercancel', resetState)
  useEventListener(document, 'pointerleave', resetState)
  useEventListener(window, 'blur', resetState)
  useEventListener(document, 'visibilitychange', () => {
    if (document.visibilityState === 'hidden') resetState()
  })

  return {
    isActive,
    cursorPosition,
    cancelDragAndDrop,
  }
}
