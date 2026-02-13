// KC: Route definition for the New Teams Conversation page.
// Auto-discovered by Vite's import.meta.glob in router/index.ts.

import type { RouteRecordRaw } from 'vue-router'

const route: RouteRecordRaw[] = [
  {
    path: '/kc/new-teams',
    name: 'KcNewTeamsConversation',
    component: () => import('./views/KcNewTeamsConversation.vue'),
    meta: {
      title: __('New Teams Chat'),
      requiresAuth: true,
      requiredPermission: ['ticket.agent'],
      level: 2,
    },
  },
]

export default route
