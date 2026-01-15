// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { useIdle, useIntervalFn, useLocalStorage } from '@vueuse/core'
import { acceptHMRUpdate, defineStore } from 'pinia'
import { computed, onScopeDispose, watch } from 'vue'

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
  const { tickTime = TICK_TIME_MS } = options

  const { idle } = useIdle(IDLE_TIME_OUT_MS)

  const isActive = computed(() => !idle.value)

  const { resume, pause } = useIntervalFn(() => {
    tickCallback(tickTime)
  }, tickTime)

  watch(isActive, (active) => (active ? resume() : pause()))

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

  // :TODO pause and activate tracking based on consent flag + second flag
  // watch()
  useTimeTracker(updateTotalUsage)

  const triggerMilestone = (key: MilestoneKey, trigger: boolean) => {
    milestoneHistory.value[key] = trigger
  }

  const currentMilestoneKey = computed<MilestoneKey | null>(() => {
    const total = typeof totalAppUsageTime.value === 'number' ? totalAppUsageTime.value : 0

    // ES2023 would be cleaner here
    // const milestone = MILESTONES.findLast((milestone) => milestone.milliseconds <= total)
    const milestone = [...MILESTONES].reverse().find((m) => m.milliseconds <= total)

    return milestone?.key ?? null
  })

  const shouldTriggerMilestoneDialog = computed(() => {
    if (!currentMilestoneKey.value) return false

    return !milestoneHistory.value[currentMilestoneKey.value]
  })

  return {
    totalAppUsageTime: computed(() => totalAppUsageTime.value),
    triggeredMilestones: computed(() => milestoneHistory.value),
    triggerMilestone,
    currentMilestoneKey,
    shouldTriggerMilestoneDialog,
  }
})

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useAppUsageStore, import.meta.hot))
}
