// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// KC: Taskbar tab plugin of a new-conversation draft, the counterpart of the
// ticket create plugin: one tab per draft, pen icon, asks before closing a
// draft with typed content.

import type { UserTaskbarTabPlugin } from '#desktop/components/UserTaskbarTabs/types.ts'

import { kcDraftTabKey, kcDraftTabLink, type KcConversationDraftKind } from './drafts.ts'

import type { Component } from 'vue'

export const buildKcDraftTabPlugin = (kind: KcConversationDraftKind, component: Component) =>
  <UserTaskbarTabPlugin>{
    type: kind.entity,
    component,
    buildEntityTabKey: (route) => kcDraftTabKey(kind, String(route.params.tabId)),
    buildTaskbarTabEntityId: (route) => route.params.tabId as string,
    // Like the legacy UI, which starts the task with `params: { id: <tab id> }`.
    buildTaskbarTabParams: (route) => ({ id: route.params.tabId }),
    // The draft has no entity (see Gql::Types::User::TaskbarItemType), the link
    //   is built from the task key.
    buildTaskbarTabLink: (_entity, tabEntityKey) => kcDraftTabLink(kind, tabEntityKey),
    confirmTabRemove: true,
  }
