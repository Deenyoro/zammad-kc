// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

/**
 * @tickTime Interval in milliseconds
 */
export interface TimeTrackerOptions {
  tickTime?: number
}

export type MilestoneKey = '1h' | '5h' | '20h'

export type MilestoneRecords = Record<MilestoneKey, { reached: boolean; triggerHistory: boolean }>

export type MilestonesHistoryRecords = Record<MilestoneKey, boolean>
