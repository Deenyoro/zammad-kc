// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import type { TicketAiAssistanceSummary } from '#shared/graphql/types.ts'

export interface SummaryItem {
  label: string
  key: keyof TicketAiAssistanceSummary
  active: boolean
}

export interface SummaryConfig {
  problem: boolean
  conversation_summary: boolean
  open_questions: boolean
  suggestions: boolean
}
