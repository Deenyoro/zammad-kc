// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { renderComponent } from '#tests/support/components/index.ts'

import { EnumTicketStateColorCode } from '#shared/graphql/types.ts'

import DragAndDropBulkCursorPreview, { type Props } from '../DragAndDropBulkCursorPreview.vue'

const mockReadFragment = vi.fn()

vi.mock('#shared/server/apollo/client.ts', () => ({
  getApolloClient: () => ({
    cache: {
      readFragment: mockReadFragment,
    },
  }),
}))

describe('DragAndDropBulkCursorPreview', () => {
  const cursorPosition = { x: 100, y: 200 }

  const renderPreview = (props: Props) => renderComponent(DragAndDropBulkCursorPreview, { props })

  beforeEach(() => {
    mockReadFragment.mockReturnValue({
      title: 'Test Ticket Title',
      stateColorCode: EnumTicketStateColorCode.Open,
    })
  })

  it('renders the ticket title from Apollo cache', () => {
    const wrapper = renderPreview({
      ticketIds: new Set(['1']),
      cursorPosition,
    })

    expect(wrapper.getByText('Test Ticket Title')).toBeInTheDocument()
  })

  it('reads the title of the last ticket in the set from the cache', () => {
    renderPreview({
      ticketIds: new Set(['1', '2', '3']),
      cursorPosition,
    })

    expect(mockReadFragment).toHaveBeenCalledWith(expect.objectContaining({ id: 'Ticket:3' }))
  })

  it('renders an empty title when cache returns null', () => {
    mockReadFragment.mockReturnValue(null)

    const wrapper = renderPreview({
      ticketIds: new Set(['1']),
      cursorPosition,
    })

    expect(wrapper.queryByText('Test Ticket Title')).not.toBeInTheDocument()
  })

  it('does not show "+ more" label with a single ticket', () => {
    const wrapper = renderPreview({
      ticketIds: new Set(['1']),
      cursorPosition,
    })

    expect(wrapper.queryByText(/more/)).not.toBeInTheDocument()
  })

  it('shows "+ N more" label when there are multiple tickets', () => {
    const wrapper = renderPreview({
      ticketIds: new Set(['1', '2', '3']),
      cursorPosition,
    })

    expect(wrapper.getByText('+ 2 more')).toBeInTheDocument()
  })

  it('positions the element based on the cursor position', () => {
    const wrapper = renderPreview({
      ticketIds: new Set(['1']),
      cursorPosition: { x: 150, y: 300 },
    })

    const container = wrapper.baseElement.querySelector('.fixed') as HTMLElement
    expect(container.style.left).toBe('134px')
    expect(container.style.top).toBe('268px')
  })

  it('renders the check-square and check-circle-no icons', () => {
    const wrapper = renderPreview({
      ticketIds: new Set(['1']),
      cursorPosition,
    })

    expect(wrapper.getByIconName('check-square')).toBeInTheDocument()
    expect(wrapper.getByIconName('check-circle-no')).toBeInTheDocument()
  })

  describe('stack layers', () => {
    it('renders no stack layers for a single ticket', () => {
      const view = renderPreview({
        ticketIds: new Set(['1']),
        cursorPosition,
      })

      expect(view.queryByTestId('2')).not.toBeInTheDocument()
      expect(view.queryByTestId('3')).not.toBeInTheDocument()
    })

    it('renders one stack layer for two tickets', () => {
      const view = renderPreview({
        ticketIds: new Set(['1', '2']),
        cursorPosition,
      })

      expect(view.queryByTestId('2')).toBeInTheDocument()
      expect(view.queryByTestId('3')).not.toBeInTheDocument()
    })

    it('renders two stack layers for three or more tickets', () => {
      const view = renderPreview({
        ticketIds: new Set(['1', '2', '3', '4']),
        cursorPosition,
      })

      expect(view.queryByTestId('2')).toBeInTheDocument()
      expect(view.queryByTestId('3')).toBeInTheDocument()
    })
  })
})
