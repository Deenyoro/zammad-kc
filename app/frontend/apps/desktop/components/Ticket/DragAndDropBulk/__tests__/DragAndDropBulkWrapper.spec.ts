// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { renderComponent } from '#tests/support/components/index.ts'
import '#tests/graphql/builders/mocks.ts'
import { mockPermissions } from '#tests/support/mock-permissions.ts'

import { mockMacrosQuery, waitForMacrosQueryCalls } from '#shared/graphql/queries/macros.mocks.ts'
import { convertToGraphQLId } from '#shared/graphql/utils.ts'

import DragAndDropBulkWrapper, { type Props } from '../DragAndDropBulkWrapper.vue'

const defaultProps: Props = {
  ticketIds: new Set<string>(['1', '2']),
  groupIds: [],
  bulkContext: { overviewId: convertToGraphQLId('Overview', '1') },
  bulkCount: 5,
  cursorPosition: { x: 100, y: 100 },
}

describe('DragAndDropBulkWrapper', () => {
  // CommonOverlayContainer teleports its backdrop to #app when fullscreen=true.
  let appDiv: HTMLDivElement

  beforeAll(() => {
    appDiv = document.createElement('div')
    appDiv.id = 'app'
    document.body.appendChild(appDiv)
  })

  afterAll(() => {
    document.body.removeChild(appDiv)
  })

  beforeEach(() => {
    mockPermissions(['ticket.agent'])
  })

  const renderWrapper = (props: Partial<Props> = {}) =>
    renderComponent(DragAndDropBulkWrapper, {
      props: { ...defaultProps, ...props },
      router: true,
    })

  describe('default rendering', () => {
    describe('top drawer', () => {
      it('renders with the macro placeholder', async () => {
        const wrapper = renderWrapper()

        mockMacrosQuery({ macros: [{ id: 'gid://zammad/Macro/1', name: 'Test Macro' }] })

        await waitForMacrosQueryCalls()
        // Because of transition
        expect(await wrapper.findByText('Run macro')).toBeVisible()
      })

      it('shows the skeleton while macros are loading', async () => {
        const wrapper = renderWrapper()

        expect(await wrapper.findByLabelText('Content loader')).toBeInTheDocument()
      })
    })

    // describe('bottom drawer', () => {
    // it('renders with the assign tickets placeholder', () => {
    // :TODO needs adjustments when we work on it
    // const wrapper = renderWrapper()
    // expect(wrapper.getByText('Assign tickets')).toBeVisible()
    // })
    // })

    it('does not show the confirmation dialog', () => {
      const wrapper = renderWrapper()
      expect(wrapper.queryByRole('dialog')).not.toBeInTheDocument()
    })

    it('shows "No macros available" when macros are loaded but empty', async () => {
      mockMacrosQuery({ macros: [] })

      const wrapper = renderWrapper()

      await waitForMacrosQueryCalls()

      expect(await wrapper.findByText('No macros available for selected tickets')).toBeVisible()
    })
  })

  describe('macros selector', () => {
    it('uses overview selector when bulk count is present', async () => {
      mockMacrosQuery({ macros: [] })

      renderWrapper()

      const calls = await waitForMacrosQueryCalls()

      expect(calls.at(-1)?.variables).toEqual({
        selector: { overviewId: convertToGraphQLId('Overview', '1') },
      })
    })

    it('uses search query selector when bulk context comes from search', async () => {
      mockMacrosQuery({ macros: [] })

      renderWrapper({
        bulkContext: { searchQuery: 'priority:1 state:open' },
      })

      const calls = await waitForMacrosQueryCalls()

      expect(calls.at(-1)?.variables).toEqual({
        selector: { searchQuery: 'priority:1 state:open' },
      })
    })

    it('uses entity ids selector when bulk count is zero', async () => {
      mockMacrosQuery({ macros: [] })

      const groupIds = [convertToGraphQLId('Group', 1), convertToGraphQLId('Group', 2)]

      renderWrapper({
        bulkCount: 0,
        groupIds,
      })

      const calls = await waitForMacrosQueryCalls()

      expect(calls.at(-1)?.variables).toEqual({
        selector: { entityIds: groupIds },
      })
    })
  })
})
