// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// KC: Routes of a new-conversation draft screen, like the ones of the ticket
// create screen: "<path>/<tab id>" is one draft (one taskbar tab), "<path>"
// starts a new draft with a fresh id - which is where the "+" menu entries
// link to - and the legacy UI's draft URL "<path>/id/<tab id>" opens the same
// draft.

import getUuid from '#shared/utils/getUuid.ts'

import type { KcConversationDraftKind } from './drafts.ts'
import type { RouteComponent, RouteRecordRaw } from 'vue-router'

interface KcDraftRouteOptions {
  name: string
  title: string
  component: () => Promise<RouteComponent>
  // Further paths that start a new draft (earlier routes of the screen).
  newDraftPaths?: string[]
}

export const buildKcDraftRoutes = (
  kind: KcConversationDraftKind,
  { name, title, component, newDraftPaths = [] }: KcDraftRouteOptions,
): RouteRecordRaw[] => [
  {
    path: `${kind.path}/:tabId`,
    name,
    props: true,
    component,
    meta: {
      title,
      requiresAuth: true,
      requiredPermission: ['ticket.agent'],
      taskbarTabEntity: kind.entity,
      isTaskbarTabPossible: (route) => !!route.params.tabId,
      level: 2,
    },
  },
  {
    path: `${kind.path}/id/:tabId`,
    redirect: (to) => ({ path: `${kind.path}/${String(to.params.tabId)}`, query: to.query }),
  },
  ...[kind.path, ...newDraftPaths].map((path): RouteRecordRaw => ({
    path,
    redirect: (to) => ({ path: `${kind.path}/${getUuid()}`, query: to.query }),
  })),
]
