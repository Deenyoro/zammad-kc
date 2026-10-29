// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// KC: taskbar tabs of the new-conversation drafts.

import { renderComponent } from '#tests/support/components/index.ts'

import { convertToGraphQLId } from '#shared/graphql/utils.ts'

import {
  kcFreepbxSmsDraft,
  kcSmsDraft,
  kcTeamsDraft,
  type KcConversationDraftKind,
} from '#desktop/entities/kc-conversation-draft/drafts.ts'

import KcConversationDraft from '../Kc/KcConversationDraft.vue'
import { userTaskbarTabPluginByType } from '../plugins/index.ts'

import type { UserTaskbarTab } from '../types.ts'
import type { RouteLocationNormalizedGeneric } from 'vue-router'

const { kcApiFetch } = vi.hoisted(() => ({ kcApiFetch: vi.fn() }))

vi.mock('#shared/composables/useKcApi.ts', () => ({ kcApiFetch }))

const taskbarTab = (kind: KcConversationDraftKind, tabId = '4711'): UserTaskbarTab => ({
  type: kind.entity,
  tabEntityKey: `${kind.keyPrefix}-${tabId}`,
  taskbarTabId: convertToGraphQLId('Taskbar', 1),
  order: 1,
  entity: null,
  updatedAt: '2026-10-29T10:00:00Z',
})

const renderTab = (kind: KcConversationDraftKind, props = {}) =>
  renderComponent(KcConversationDraft, {
    props: {
      taskbarTab: taskbarTab(kind),
      taskbarTabLink: `${kind.path}/4711`,
      ...props,
    },
    router: true,
    store: true,
  })

describe('KcConversationDraft taskbar tab', () => {
  it('shows the recipient of the stored draft, like the legacy UI', async () => {
    kcApiFetch.mockResolvedValue({
      exists: true,
      state: { phone_number: '+15555550111, +15555550122', body: 'Hello' },
    })

    const view = renderTab(kcSmsDraft)

    expect(
      await view.findByRole('link', { name: 'SMS: +15555550111, +15555550122' }),
    ).toHaveAttribute('href', '/desktop/kc/new_rcsms/4711')
    expect(view.getByIconName('pencil')).toBeInTheDocument()
    expect(kcApiFetch).toHaveBeenCalledWith('/conversations/draft_state?key=KcNewSmsScreen-4711')
  })

  it('shows the plain label for a draft without a recipient', async () => {
    kcApiFetch.mockResolvedValue({ exists: false, state: {} })

    const view = renderTab(kcFreepbxSmsDraft)

    expect(await view.findByRole('link', { name: 'SMS (FreePBX)' })).toBeInTheDocument()
  })

  it('names the Teams contact', async () => {
    kcApiFetch.mockResolvedValue({
      exists: true,
      state: { teams_user_id: 'aad-1', display_name: 'Jane Doe', body: '' },
    })

    const view = renderTab(kcTeamsDraft)

    expect(await view.findByRole('link', { name: 'Teams Message: Jane Doe' })).toBeInTheDocument()
  })

  it('prefers the open form over the stored one, without reading it', () => {
    const view = renderTab(kcSmsDraft, {
      context: { formValues: { phone_number: '+15555550133', body: '' } },
    })

    expect(view.getByRole('link', { name: 'SMS: +15555550133' })).toBeInTheDocument()
    expect(kcApiFetch).not.toHaveBeenCalled()
  })
})

describe('KC draft taskbar tab plugins', () => {
  const route = (tabId: string) =>
    ({ params: { tabId }, query: {} }) as unknown as RouteLocationNormalizedGeneric

  it.each([
    [kcSmsDraft, 'KcNewSmsConversationContent', 'KcNewSmsScreen', '/kc/new_rcsms'],
    [
      kcFreepbxSmsDraft,
      'KcNewFreepbxSmsConversationContent',
      'KcNewFreepbxSmsScreen',
      '/kc/new_freepbx_sms',
    ],
    [kcTeamsDraft, 'KcNewTeamsConversationContent', 'KcNewTeamsScreen', '/kc/new_teams'],
  ])(
    'uses the task key, callback and params of the legacy UI (%#)',
    (kind, callback, keyPrefix, path) => {
      const plugin = userTaskbarTabPluginByType[kind.entity]

      expect(plugin.type).toBe(callback)
      expect(plugin.buildEntityTabKey(route('abc-123'))).toBe(`${keyPrefix}-abc-123`)
      expect(plugin.buildTaskbarTabParams?.(route('abc-123'))).toEqual({ id: 'abc-123' })
      expect(plugin.buildTaskbarTabLink?.(null, `${keyPrefix}-abc-123`)).toBe(`${path}/abc-123`)
      expect(plugin.buildTaskbarTabLink?.(null, 'TicketCreateScreen-1')).toBeUndefined()
      expect(plugin.confirmTabRemove).toBe(true)
    },
  )
})
