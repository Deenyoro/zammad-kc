// KC: Route definition for the New SMS Message (FreePBX) page.
// Auto-discovered by Vite's import.meta.glob in router/index.ts.

import type { RouteRecordRaw } from 'vue-router'

const route: RouteRecordRaw[] = [
  {
    path: '/kc/new_freepbx_sms',
    name: 'KcNewFreepbxSmsConversation',
    component: () => import('./views/KcNewFreepbxSmsConversation.vue'),
    meta: {
      title: __('New SMS Message (FreePBX)'),
      requiresAuth: true,
      requiredPermission: ['ticket.agent'],
      level: 2,
    },
  },
]

export default route
