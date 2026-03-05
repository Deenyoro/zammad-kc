// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import renderComponent, { initializePiniaStore } from '#tests/support/components/renderComponent.ts'
import { mockPermissions } from '#tests/support/mock-permissions.ts'
import { waitForNextTick } from '#tests/support/utils.ts'

import '#tests/graphql/builders/mocks.ts'

import { EnumBulkUpdateStatusStatus } from '#shared/graphql/types.ts'
import { convertToGraphQLId } from '#shared/graphql/utils.ts'

import TicketBulkEditButton from '#desktop/components/Ticket/TicketBulkEditButton.vue'
import { useTicketBulkUpdateStore } from '#desktop/entities/user/current/stores/ticketBulkUpdate.ts'

describe('TicketBulkEditButton', () => {
  it('render correctly without any id', async () => {
    mockPermissions(['ticket.agent'])

    const wrapper = renderComponent(TicketBulkEditButton, {
      props: {
        checkedTicketIds: new Set(),
      },
    })

    expect(wrapper.queryByRole('button', { name: 'Bulk actions' })).not.toBeInTheDocument()

    const checkedTicketIds = new Set([convertToGraphQLId('Ticket', 2)])

    await wrapper.rerender({
      checkedTicketIds,
    })

    expect(wrapper.getByRole('button', { name: 'Bulk actions' })).toHaveTextContent('Bulk actions')
    expect(wrapper.getByIconName('collection-play')).toBeInTheDocument()
  })

  it("doesn't render for customer user", () => {
    mockPermissions(['ticket.customer'])

    const wrapper = renderComponent(TicketBulkEditButton, {
      props: {
        checkedTicketIds: new Set(),
      },
    })

    expect(wrapper.queryByTestId('ticket-bulk-edit-button')).not.toBeInTheDocument()
  })

  it('emits open flyout event', async () => {
    mockPermissions(['ticket.agent'])

    const checkedTicketIds = new Set([convertToGraphQLId('Ticket', 2)])

    const wrapper = renderComponent(TicketBulkEditButton, {
      props: {
        checkedTicketIds,
      },
    })

    await wrapper.events.click(wrapper.getByTestId('ticket-bulk-edit-button'))

    expect(wrapper.emitted('open-flyout')).toBeTruthy()
  })

  it('disables button when bulk update is running', async () => {
    mockPermissions(['ticket.agent'])
    initializePiniaStore()

    const checkedTicketIds = new Set([convertToGraphQLId('Ticket', 2)])

    const wrapper = renderComponent(TicketBulkEditButton, {
      props: {
        checkedTicketIds,
      },
      store: true,
    })

    expect(wrapper.queryByRole('button', { name: 'Bulk in progress…' })).not.toBeInTheDocument()
    expect(wrapper.getByRole('button', { name: 'Bulk actions' })).toBeInTheDocument()
    expect(wrapper.getByRole('button', { name: 'Bulk actions' })).not.toBeDisabled()

    const { setTicketBulkUpdateStatus } = useTicketBulkUpdateStore()
    setTicketBulkUpdateStatus({
      status: EnumBulkUpdateStatusStatus.Running,
      processedCount: 0,
      total: 5,
    })

    await waitForNextTick()

    expect(wrapper.getByRole('button', { name: 'Bulk in progress…' })).toBeInTheDocument()
    expect(wrapper.getByRole('button', { name: 'Bulk in progress…' })).toBeDisabled()
  })
})
