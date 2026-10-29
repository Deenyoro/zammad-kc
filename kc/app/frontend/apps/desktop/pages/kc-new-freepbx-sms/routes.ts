// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// KC: Routes of the New SMS Message (FreePBX) screen.
// Auto-discovered by Vite's import.meta.glob in router/index.ts.
//
// Every draft is a taskbar tab (see buildKcDraftRoutes): /kc/new_freepbx_sms
// starts a new one, /kc/new_freepbx_sms/<tab id> opens it.

import { buildKcDraftRoutes } from '#desktop/entities/kc-conversation-draft/buildKcDraftRoutes.ts'
import { kcFreepbxSmsDraft } from '#desktop/entities/kc-conversation-draft/drafts.ts'

import type { RouteRecordRaw } from 'vue-router'

const route: RouteRecordRaw[] = buildKcDraftRoutes(kcFreepbxSmsDraft, {
  name: 'KcNewFreepbxSmsConversation',
  title: __('New SMS Message (FreePBX)'),
  component: () => import('./views/KcNewFreepbxSmsConversation.vue'),
})

export default route
