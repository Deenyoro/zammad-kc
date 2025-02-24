// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { EnumTaskbarEntity } from '#shared/graphql/types.ts'

import type { RouteRecordRaw } from 'vue-router'

const route: RouteRecordRaw[] = [
  {
    path: '/search/:searchTerm?',
    name: 'search',
    props: true,
    component: () => import('./views/Search.vue'),
    meta: {
      title: __('Search'),
      requiresAuth: true,
      requiredPermission: ['ticket.agent', 'ticket.customer'],
      taskbarTabEntity: EnumTaskbarEntity.Search,
      level: 2,
    },
  },
]

export default route
