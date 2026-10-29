// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// KC: Routes of the New SMS Conversation (RingCentral) screen.
// Auto-discovered by Vite's import.meta.glob in router/index.ts.
//
// Every draft is a taskbar tab (see buildKcDraftRoutes): /kc/new_rcsms starts
// a new one, /kc/new_rcsms/<tab id> opens it.

import { buildKcDraftRoutes } from '#desktop/entities/kc-conversation-draft/buildKcDraftRoutes.ts'
import { kcSmsDraft } from '#desktop/entities/kc-conversation-draft/drafts.ts'

import type { RouteRecordRaw } from 'vue-router'

const route: RouteRecordRaw[] = buildKcDraftRoutes(kcSmsDraft, {
  name: 'KcNewSmsConversation',
  title: __('New SMS Message (RingCentral)'),
  component: () => import('./views/KcNewSmsConversation.vue'),
})

export default route
