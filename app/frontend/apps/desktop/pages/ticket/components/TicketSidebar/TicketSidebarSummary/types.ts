// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import type { TicketAiAssistanceSummary } from '#shared/graphql/types.ts'

export enum TicketSummaryFeature {
  Checklist = 'checklist',
}

export interface SummaryItem {
  label: string
  key: keyof TicketAiAssistanceSummary
  feature?: TicketSummaryFeature
  active: boolean
}

export interface SummaryConfig {
  problem: boolean
  conversation_summary: boolean
  open_questions: boolean
  suggestions: boolean
  generate_on: string
}
