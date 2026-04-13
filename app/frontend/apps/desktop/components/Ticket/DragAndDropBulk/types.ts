// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import type {
  TicketBulkOverviewContext,
  TicketBulkSearchContext,
} from '#desktop/components/Ticket/TicketBulkEditFlyout/useTicketBulkEdit.ts'

import type { Ref } from 'vue'

export interface DragAndDropBulkOptions {
  checkedTicketIds: Ref<Set<ID>>
  bulkContext: Ref<TicketBulkOverviewContext | TicketBulkSearchContext | undefined>
  bulkCount: Ref<number | undefined>
}

export enum DragAndDropBulkEntityType {
  Macro = 'macro',
  Ticket = 'ticket',
}

export interface BulkData {
  id: ID
  type: DragAndDropBulkEntityType
}
