// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// KC: Routes of the New Teams Conversation screen.
// Auto-discovered by Vite's import.meta.glob in router/index.ts.
//
// Every draft is a taskbar tab (see buildKcDraftRoutes): /kc/new_teams starts
// a new one, /kc/new_teams/<tab id> opens it. The path matches the legacy UI's
// ("#kc/new_teams"); the earlier /kc/new-teams still starts a draft.

import { buildKcDraftRoutes } from '#desktop/entities/kc-conversation-draft/buildKcDraftRoutes.ts'
import { kcTeamsDraft } from '#desktop/entities/kc-conversation-draft/drafts.ts'

import type { RouteRecordRaw } from 'vue-router'

const route: RouteRecordRaw[] = buildKcDraftRoutes(kcTeamsDraft, {
  name: 'KcNewTeamsConversation',
  title: __('New Teams Message'),
  component: () => import('./views/KcNewTeamsConversation.vue'),
  newDraftPaths: ['/kc/new-teams'],
})

export default route
