// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// KC: routes of the new-conversation drafts.

import { createMemoryHistory, createRouter, type RouteRecordRaw } from 'vue-router'

import smsRoutes from '#desktop/pages/kc-new-sms/routes.ts'
import teamsRoutes from '#desktop/pages/kc-new-teams/routes.ts'

import { kcSmsDraft, kcTeamsDraft } from '../drafts.ts'

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

const Stub = { render: () => null }

// The screens themselves are not loaded here.
const stubbed = (routes: RouteRecordRaw[]) =>
  routes.map((route) =>
    'component' in route ? ({ ...route, component: Stub } as RouteRecordRaw) : route,
  )

const buildRouter = () =>
  createRouter({
    history: createMemoryHistory(),
    routes: [...stubbed(smsRoutes), ...stubbed(teamsRoutes), { path: '/', component: Stub }],
  })

describe('KC draft routes', () => {
  it('starts a new draft with a tab id of its own on every visit of the "+" link', async () => {
    const router = buildRouter()

    await router.push('/kc/new_rcsms')
    const first = router.currentRoute.value

    await router.push('/')
    await router.push('/kc/new_rcsms')
    const second = router.currentRoute.value

    expect(first.name).toBe('KcNewSmsConversation')
    expect(first.params.tabId).toMatch(UUID)
    expect(second.params.tabId).toMatch(UUID)
    expect(second.params.tabId).not.toBe(first.params.tabId)
  })

  it('opens a draft as a taskbar tab of the draft callback', async () => {
    const router = buildRouter()

    await router.push('/kc/new_rcsms/4711')

    const { meta, params } = router.currentRoute.value
    expect(params.tabId).toBe('4711')
    expect(meta.taskbarTabEntity).toBe(kcSmsDraft.entity)
    expect(meta.isTaskbarTabPossible?.(router.currentRoute.value)).toBe(true)
  })

  it('opens the draft of a legacy UI URL', async () => {
    const router = buildRouter()

    await router.push('/kc/new_teams/id/12345')

    expect(router.currentRoute.value.path).toBe('/kc/new_teams/12345')
    expect(router.currentRoute.value.meta.taskbarTabEntity).toBe(kcTeamsDraft.entity)
  })

  it('keeps the earlier Teams path working', async () => {
    const router = buildRouter()

    await router.push('/kc/new-teams')

    expect(router.currentRoute.value.name).toBe('KcNewTeamsConversation')
    expect(router.currentRoute.value.params.tabId).toMatch(UUID)
  })
})
