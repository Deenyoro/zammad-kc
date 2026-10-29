// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// KC: The new-conversation drafts (RingCentral SMS, FreePBX SMS, Teams chat)
// as taskbar tabs of the desktop view.
//
// Every "+ New SMS ..." opens a draft of its own, kept as a taskbar task like
// the ticket create screen. The task is the very one the legacy UI uses
// (kc_conversation_draft.coffee): same key ("KcNewSmsScreen-<id>"), callback
// ("KcNewSmsConversationContent") and state field names, so a draft started
// in one UI is listed - and restored - in the other. The backend registers
// the callbacks as taskbar entities (Kc::TaskbarConversationDraftEntities).

import { kcApiFetch } from '#shared/composables/useKcApi.ts'
import type { EnumTaskbarEntity } from '#shared/graphql/types.ts'
import { i18n } from '#shared/i18n.ts'

export type KcDraftState = Record<string, unknown>

export interface KcConversationDraftKind {
  // Taskbar callback, a value of the TaskbarEntityType enum on the server.
  entity: EnumTaskbarEntity
  // Task key prefix, the key is "<prefix>-<tab id>".
  keyPrefix: string
  // Route of the screen without the tab id.
  path: string
  // Untranslated tab label.
  label: string
  // Text behind the label ("SMS: +15555550100").
  detail: (state: KcDraftState) => string
  // Whether the form holds anything typed by the agent.
  hasContent: (state: KcDraftState) => boolean
}

const text = (value: unknown) => (typeof value === 'string' ? value.trim() : '')

// The generated EnumTaskbarEntity holds upstream's values only. The KC ones are
//   enum values on the server all the same, so a cast is all that is missing.
const kcTaskbarEntity = (callback: string) => callback as EnumTaskbarEntity

export const kcSmsDraft: KcConversationDraftKind = {
  entity: kcTaskbarEntity('KcNewSmsConversationContent'),
  keyPrefix: 'KcNewSmsScreen',
  path: '/kc/new_rcsms',
  label: __('SMS'),
  detail: (state) => text(state.phone_number),
  hasContent: (state) => !!(text(state.phone_number) || text(state.body)),
}

export const kcFreepbxSmsDraft: KcConversationDraftKind = {
  entity: kcTaskbarEntity('KcNewFreepbxSmsConversationContent'),
  keyPrefix: 'KcNewFreepbxSmsScreen',
  path: '/kc/new_freepbx_sms',
  label: __('SMS (FreePBX)'),
  detail: (state) => text(state.phone_number),
  hasContent: (state) => !!(text(state.phone_number) || text(state.body)),
}

export const kcTeamsDraft: KcConversationDraftKind = {
  entity: kcTaskbarEntity('KcNewTeamsConversationContent'),
  keyPrefix: 'KcNewTeamsScreen',
  path: '/kc/new_teams',
  label: __('Teams Message'),
  detail: (state) => text(state.display_name),
  hasContent: (state) => !!(text(state.teams_user_id) || text(state.body)),
}

export const kcConversationDrafts = [kcSmsDraft, kcFreepbxSmsDraft, kcTeamsDraft]

export const kcConversationDraftByEntity = (entity: EnumTaskbarEntity) =>
  kcConversationDrafts.find((kind) => kind.entity === entity)

export const kcDraftTabKey = (kind: KcConversationDraftKind, tabId: string) =>
  `${kind.keyPrefix}-${tabId}`

export const kcDraftTabId = (kind: KcConversationDraftKind, tabEntityKey: string) => {
  const prefix = `${kind.keyPrefix}-`
  if (!tabEntityKey.startsWith(prefix)) return

  return tabEntityKey.slice(prefix.length) || undefined
}

export const kcDraftTabLink = (kind: KcConversationDraftKind, tabEntityKey?: string) => {
  const tabId = tabEntityKey && kcDraftTabId(kind, tabEntityKey)
  if (!tabId) return

  return `${kind.path}/${tabId}`
}

// Tab label like the legacy UI shows it: "SMS: +15555550100", "Teams Message: Jane Doe".
export const kcDraftTitle = (kind: KcConversationDraftKind, state: KcDraftState) => {
  const label = i18n.t(kind.label)
  const detail = kind.detail(state)

  return detail ? `${label}: ${detail}` : label
}

export interface KcDraftStateResponse {
  exists: boolean
  state: KcDraftState
}

// The stored form of one of the agent's own drafts. The GraphQL taskbar list of
//   the desktop view carries no task state, the KC endpoint reads just this one.
export const fetchKcDraftState = (tabEntityKey: string) =>
  kcApiFetch<KcDraftStateResponse>(
    `/conversations/draft_state?key=${encodeURIComponent(tabEntityKey)}`,
  )
