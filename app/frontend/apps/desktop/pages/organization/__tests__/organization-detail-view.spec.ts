// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { within } from '@testing-library/vue'

import { visitView } from '#tests/support/components/visitView.ts'
import { mockApplicationConfig } from '#tests/support/mock-applicationConfig.ts'
import { mockPermissions } from '#tests/support/mock-permissions.ts'

import { mockOrganizationQuery } from '#shared/entities/organization/graphql/queries/organization.mocks.ts'
import { createDummyTicket } from '#shared/entities/ticket-article/__tests__/mocks/ticket.ts'
import { EnumTicketStateTypeCategory, type Organization } from '#shared/graphql/types.ts'
import { convertToGraphQLId } from '#shared/graphql/utils.ts'

import {
  mockTicketsByOrganizationQuery,
  waitForTicketsByOrganizationQueryCalls,
} from '#desktop/entities/ticket/graphql/queries/ticketsByOrganization.mocks.ts'
import { getTicketByOrganizationUpdatesSubscriptionHandler } from '#desktop/entities/ticket/graphql/subscriptions/ticketByOrganizationUpdates.mocks.ts'

const copyToClipboardMock = vi.fn()

vi.mock('#shared/composables/useCopyToClipboard.ts', async () => ({
  useCopyToClipboard: () => ({ copyToClipboard: copyToClipboardMock }),
}))

const organizationData: Organization = {
  id: convertToGraphQLId('Organization', 1),
  internalId: 1,
  name: 'Zammad Foundation',
  shared: true,
  domain: '',
  domainAssignment: false,
  active: true,
  note: '<p dir="auto">note test</p><p dir="auto"></p>',
  vip: false,
  objectAttributeValues: [],
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  createdBy: null,
  updatedBy: null,
  __typename: 'Organization',
  allMembers: {
    edges: [
      {
        node: {
          id: convertToGraphQLId('User', 2),
          internalId: 2,
          image: null,
          firstname: 'Nicole',
          lastname: 'Braun',
          fullname: 'Nicole Braun',
          email: 'nicole.braun@zammad.org',
          phone: '22',
          outOfOffice: false,
          outOfOfficeStartAt: null,
          outOfOfficeEndAt: null,
          active: true,
          vip: false,
          createdAt: '2026-01-01T00:00:00Z',
          updatedAt: '2026-01-01T00:00:00Z',
          policy: { update: true, destroy: true, __typename: 'PolicyDefault' },
          __typename: 'User',
        },
        cursor: 'MQ', // 🤔 should not be in the type
        __typename: 'UserEdge',
      },
    ],
    pageInfo: {
      endCursor: 'MQ',
      hasNextPage: false,
      hasPreviousPage: false,
      __typename: 'PageInfo',
    },
    totalCount: 1,
    __typename: 'UserConnection',
  },
  policy: {
    update: true,
    destroy: true,
    __typename: 'PolicyDefault',
  },
  ticketsCount: {
    open: 11,
    closed: 6,
    organizationOpen: 11,
    organizationClosed: 6,
    __typename: 'TicketCount',
  },
}

const visitOrganizationView = async () => {
  const view = await visitView(`organization/profile/${organizationData.internalId}`)

  const main = view.getByRole('main')
  const header = within(main).getByTestId('organization-detail-top-bar')

  return { view, main, header }
}

describe('Organization Detail View', () => {
  beforeEach(async () => {
    mockApplicationConfig({
      fqdn: 'zammad.example.com',
      http_type: 'http',
    })

    mockPermissions(['ticket.agent'])

    mockOrganizationQuery({
      organization: organizationData,
    })
  })

  describe('displays breadcrumb navigation', () => {
    it('displays breadcrumb navigation', async () => {
      const { header } = await visitOrganizationView()

      const breadcrumb = within(header).getByRole('navigation', { name: 'Breadcrumb navigation' })
      const items = within(breadcrumb).getAllByRole('listitem')

      expect(items).toHaveLength(2)
      expect(items[0]).toHaveTextContent('Organization')
      expect(within(items[1]).getByRole('heading')).toHaveAccessibleName('Zammad Foundation')
    })

    it('copies organization name', async () => {
      const { view, header } = await visitOrganizationView()

      const breadcrumb = within(header).getByRole('navigation', { name: 'Breadcrumb navigation' })

      await view.events.click(
        within(breadcrumb).getByRole('button', { name: 'Copy organization display name' }),
      )

      expect(copyToClipboardMock).toHaveBeenCalledWith([
        {
          data: {
            'text/html':
              '<a href="http://zammad.example.com/desktop/organizations/1">Zammad Foundation</a>',
            'text/plain': 'Zammad Foundation',
          },
          options: {
            presentationStyle: 'unspecified',
          },
        },
      ])
    })

    it('displays basic organization information', async () => {
      const { header } = await visitOrganizationView()

      expect(within(header).getByLabelText('Avatar (Zammad Foundation)')).toBeVisible()
      expect(within(header).getByText('Zammad Foundation', { selector: 'span' })).toBeVisible()
    })

    it.todo('displays actions for agent users')

    it.todo('displays actions for admin users')

    it.todo('displays additional actions on some organization profiles')
  })

  describe('Object attributes', () => {
    it('displays organization attributes', async () => {
      const { main } = await visitOrganizationView()

      expect(within(main).getByText('Shared organization').parentElement).toHaveTextContent('yes')
      expect(within(main).getByText('Domain based assignment').parentElement).toHaveTextContent(
        'no',
      )
    })
  })

  describe.skip('Organization members', () => {
    it('displays list of organization members', async () => {
      const { main } = await visitOrganizationView()

      expect(main).toBeInTheDocument()
    })

    it('displays member details (name, email, role)', async () => {})

    it('shows member count', async () => {})
  })

  describe('Organization tickets', () => {
    beforeEach(() => {
      const dummyTickets = Array.from({ length: 7 }, () => createDummyTicket())

      mockTicketsByOrganizationQuery((variables) => {
        const totalCount = variables.stateTypeCategory === EnumTicketStateTypeCategory.Open ? 4 : 3
        const start = variables.stateTypeCategory === EnumTicketStateTypeCategory.Open ? 0 : 3
        const end = totalCount - 1

        return {
          ticketsByOrganization: {
            totalCount,
            edges: dummyTickets.slice(start, end).map((ticket) => ({
              node: ticket,
            })),
          },
        }
      })
    })

    it('displays organization tickets section', async () => {
      const { main } = await visitOrganizationView()

      const calls = await waitForTicketsByOrganizationQueryCalls()

      expect(calls).toHaveLength(2)

      const organizationTicketsSection = within(main).getByRole('region', {
        name: 'Organization tickets',
      })

      expect(
        within(organizationTicketsSection).getByRole('heading', {
          name: 'Organization tickets',
          level: 2,
        }),
      ).toBeVisible()

      const openTicketsHeading = await within(organizationTicketsSection).findByRole('heading', {
        name: 'Open tickets',
      })

      expect(openTicketsHeading).toHaveTextContent('4')

      const closedTicketsHeading = await within(organizationTicketsSection).findByRole('heading', {
        name: 'Closed tickets',
      })

      expect(closedTicketsHeading).toHaveTextContent('3')
    })

    it('refetch tickets when organization subscription triggers', async () => {
      await visitOrganizationView()

      const calls = await waitForTicketsByOrganizationQueryCalls()

      expect(calls).toHaveLength(2)

      await getTicketByOrganizationUpdatesSubscriptionHandler().trigger({
        ticketByOrganizationUpdates: {
          listChanged: true,
        },
      })

      expect(calls).toHaveLength(4)
    })
  })

  describe.skip('Ticket frequency chart', () => {
    it('renders a chart', async () => {})

    it('refetch chart data when organization subscription triggers', async () => {})
  })
})
