// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { useIdle, useIntervalFn, useLocalStorage } from '@vueuse/core'
import { acceptHMRUpdate, defineStore } from 'pinia'
import { computed, onScopeDispose, watch } from 'vue'

import { useBetaUi } from '#desktop/components/BetaUi/composables/useBetaUi.ts'
import { useBetaUiFeedbackConsentState } from '#desktop/components/BetaUi/composables/useBetaUiFeedbackConsentState.ts'
import type {
  MilestonesHistoryRecords,
  MilestoneKey,
  TimeTrackerOptions,
} from '#desktop/types/appUsage.ts'

const TICK_TIME_MS = 30 * 1000 // Update interval: 30 seconds in milliseconds
const IDLE_TIME_OUT_MS = 5 * 60 * 1000 // 5 minutes in milliseconds

const MILESTONES = [
  { key: '1h', milliseconds: 60 * 60 * 1000 }, // 1 hour
  { key: '5h', milliseconds: 5 * 60 * 60 * 1000 }, // 5 hours
  { key: '20h', milliseconds: 20 * 60 * 60 * 1000 }, // 20 hours
] as const

const useTimeTracker = (tickCallback: (time: number) => void, options: TimeTrackerOptions = {}) => {
  const { tickTime = TICK_TIME_MS, enabled = () => true } = options

  const { idle } = useIdle(IDLE_TIME_OUT_MS)

  const isActive = computed(() => !idle.value)
  const runTimer = computed(enabled)

  const { resume, pause } = useIntervalFn(
    () => {
      tickCallback(tickTime)
    },
    tickTime,
    { immediate: false },
  )

  watch(
    [isActive, runTimer],
    ([active, run]) => {
      return active && run ? resume() : pause()
    },
    { immediate: true },
  )

  onScopeDispose(pause)

  return { resume, pause }
}

export const useAppUsageStore = defineStore('appUsage', () => {
  const milestoneHistory = useLocalStorage<MilestonesHistoryRecords>(
    'app-usage-milestones-trigger-history',
    () => ({
      '1h': false,
      '5h': false,
      '20h': false,
    }),
  )
  /*
   * Total usage counter in milliseconds
   */
  const totalAppUsageTime = useLocalStorage('app-usage-total-time', 0)

  const resetTotalAppUsageTime = () => {
    totalAppUsageTime.value = 0
  }

  const updateTotalUsage = (millisecondsCount: number) => {
    if (typeof totalAppUsageTime.value !== 'number') resetTotalAppUsageTime()

    totalAppUsageTime.value += millisecondsCount
  }

  const { hasFeedbackConsent } = useBetaUiFeedbackConsentState()
  const { switchValue, betaUiSwitchAvailable } = useBetaUi()

  useTimeTracker(updateTotalUsage, {
    enabled: () =>
      !!betaUiSwitchAvailable.value && !!switchValue.value && hasFeedbackConsent.value === 'true',
  })

  const triggerMilestone = (key: MilestoneKey) => {
    milestoneHistory.value[key] = true
  }

  const currentMilestoneKey = computed<MilestoneKey | null>(() => {
    const total = typeof totalAppUsageTime.value === 'number' ? totalAppUsageTime.value : 0

    // ES2023 would be cleaner here
    // const milestone = MILESTONES.findLast((milestone) => milestone.milliseconds <= total)
    const milestone = [...MILESTONES].reverse().find((m) => m.milliseconds <= total)

    return milestone?.key ?? null
  })

  const neverAskAgainForTimedFeedback = useLocalStorage(
    'beta-ui-feedback-never-ask-again-timed',
    false,
  )

  const setNeverAskAgainForTimedFeedback = (value = true) => {
    neverAskAgainForTimedFeedback.value = value
  }

  const shouldTriggerMilestoneDialog = computed(() => {
    if (!currentMilestoneKey.value || !hasFeedbackConsent.value) return false

    return (
      !milestoneHistory.value[currentMilestoneKey.value] && !neverAskAgainForTimedFeedback.value
    )
  })

  return {
    totalAppUsageTime: computed(() => totalAppUsageTime.value),
    triggeredMilestones: computed(() => milestoneHistory.value),
    triggerMilestone,
    currentMilestoneKey,
    shouldTriggerMilestoneDialog,
    setNeverAskAgainForTimedFeedback,
  }
})

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useAppUsageStore, import.meta.hot))
}
