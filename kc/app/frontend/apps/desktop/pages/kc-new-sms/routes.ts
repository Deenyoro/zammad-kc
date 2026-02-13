// KC: Route definition for the New SMS Conversation page.
// Auto-discovered by Vite's import.meta.glob in router/index.ts.

import type { RouteRecordRaw } from 'vue-router'

const route: RouteRecordRaw[] = [
  {
    path: '/kc/new-sms',
    name: 'KcNewSmsConversation',
    component: () => import('./views/KcNewSmsConversation.vue'),
    meta: {
      title: __('New SMS'),
      requiresAuth: true,
      requiredPermission: ['ticket.agent'],
      level: 2,
    },
  },
]

export default route
