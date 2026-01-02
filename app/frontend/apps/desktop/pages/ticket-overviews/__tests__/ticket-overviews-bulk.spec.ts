// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { visitView } from '#tests/support/components/visitView.ts'
import { mockPermissions } from '#tests/support/mock-permissions.ts'
import { mockUserCurrent } from '#tests/support/mock-userCurrent.ts'

import { mockFormUpdaterQuery } from '#shared/components/Form/graphql/queries/formUpdater.mocks.ts'
import { createDummyTicket } from '#shared/entities/ticket-article/__tests__/mocks/ticket.ts'
import { convertToGraphQLId } from '#shared/graphql/utils.ts'

import { waitForTicketUpdateBulkMutationCalls } from '#desktop/entities/ticket/graphql/mutations/updateBulk.mocks.ts'
import { waitForTicketsCachedByOverviewQueryCalls } from '#desktop/entities/ticket/graphql/queries/ticketsCachedByOverview.mocks.ts'
import { waitForUserCurrentTicketOverviewsQueryCalls } from '#desktop/entities/ticket/graphql/queries/userCurrentTicketOverviews.mocks.ts'

import {
  mockDefaultOverviewQueries,
  mockDefaultTicketsCachedByOverview,
} from './mocks/ticket-overviews-mocks.ts'

describe('Ticket Overviews > Bulk edit tickets', () => {
  it('does not show bulk edit button when user is customer', async () => {
    mockDefaultOverviewQueries()

    mockPermissions(['ticket.customer'])

    mockUserCurrent({
      preferences: {
        overviews_last_used: {
          '1': '2021-06-01T00:00:00.000Z',
          '2': '2021-06-01T00:00:00.000Z',
        },
      },
    })

    const view = await visitView('tickets/view/my_assigned')

    expect(view.queryByRole('checkbox')).not.toBeInTheDocument()
    expect(view.queryByRole('button', { name: 'Bulk Actions' })).not.toBeInTheDocument()
  })

  it('selects a ticket for bulk edit', async () => {
    mockDefaultOverviewQueries()

    const ticket = createDummyTicket()

    mockDefaultTicketsCachedByOverview({
      edges: [{ node: ticket }],
    })

    mockUserCurrent({
      permissions: {
        names: ['ticket.agent'],
      },
      preferences: {
        overviews_last_used: {},
      },
    })

    mockFormUpdaterQuery({
      formUpdater: {
        fields: {
          group_id: {
            options: [
              {
                value: 2,
                label: 'test group',
              },
            ],
          },
          owner_id: {
            options: [
              {
                value: 3,
                label: 'Test Admin Agent',
              },
            ],
          },
          state_id: {
            options: [
              {
                value: 4,
                label: 'closed',
              },
            ],
          },
          pending_time: {
            show: false,
          },
        },
      },
    })

    const view = await visitView('tickets/view/my_assigned')

    await waitForUserCurrentTicketOverviewsQueryCalls()

    expect(view.queryByRole('button', { name: 'Bulk Action' })).not.toBeInTheDocument()

    await view.events.click(view.getByRole('checkbox', { name: 'Select this entry' }))

    await view.events.click(view.getByRole('button', { name: 'Bulk Actions' }))

    expect(
      await view.findByRole('complementary', { name: 'Tickets Bulk Edit' }),
    ).toBeInTheDocument()

    const ticketState = await view.findByLabelText('State')

    await view.events.click(ticketState)

    expect(await view.findByRole('menu')).toBeInTheDocument()

    await view.events.click(view.getByRole('option', { name: 'closed' }))

    await view.events.click(view.getByRole('button', { name: 'Apply' }))

    const calls = await waitForTicketUpdateBulkMutationCalls()

    expect(calls.at(-1)?.variables).toEqual({
      input: {
        article: null,
        stateId: convertToGraphQLId('Ticket::State', 4),
      },
      ticketIds: [ticket.id],
    })

    expect(await waitForTicketsCachedByOverviewQueryCalls()).toHaveLength(2)
  })
})
