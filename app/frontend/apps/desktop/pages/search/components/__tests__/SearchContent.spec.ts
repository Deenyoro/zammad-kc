// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { within, waitFor } from '@testing-library/vue'

import ticketObjectAttributes from '#tests/graphql/factories/fixtures/ticket-object-attributes.ts'
import { renderComponent } from '#tests/support/components/index.ts'
import { getTestRouter } from '#tests/support/components/renderComponent.ts'
import { mockPermissions } from '#tests/support/mock-permissions.ts'
import { mockRouterHooks } from '#tests/support/mock-vue-router.ts'

import { mockObjectManagerFrontendAttributesQuery } from '#shared/entities/object-attributes/graphql/queries/objectManagerFrontendAttributes.mocks.ts'
import {
  EnumSearchableModels,
  EnumTicketStateColorCode,
} from '#shared/graphql/types.ts'
import { convertToGraphQLId } from '#shared/graphql/utils.ts'

import {
  mockDetailSearchQuery,
  waitForDetailSearchQueryCalls,
} from '#desktop/components/Search/graphql/queries/detailSearch.mocks.ts'
import {
  mockSearchCountsQuery,
  waitForSearchCountsQueryCalls,
} from '#desktop/components/Search/graphql/queries/searchCounts.mocks.ts'
import SearchContent from '#desktop/pages/search/components/SearchContent.vue'

mockRouterHooks()

const renderSearchContent = () => {
  mockObjectManagerFrontendAttributesQuery({
    objectManagerFrontendAttributes: ticketObjectAttributes(),
  })

  const wrapper = renderComponent(SearchContent, { router: true, form: true })
  return { wrapper }
}

describe('SearchContent', () => {
  it('displays breadcrumbs', async () => {
    mockPermissions(['ticket.agent'])
    mockDetailSearchQuery({
      search: {
        totalCount: 1,
        items: [
          {
            id: convertToGraphQLId('Ticket', 469),
            internalId: 469,
            title: 'Foot ticket title',
            number: '12468',
            customer: {
              id: convertToGraphQLId('User', 2),
              fullname: 'Nicole Braun User',
            },
            group: {
              id: convertToGraphQLId('Group', 6),
              name: 'Group 1',
            },
            state: {
              id: convertToGraphQLId('State', 2),
              name: 'open',
            },
            stateColorCode: EnumTicketStateColorCode.Open,
            priority: {
              id: convertToGraphQLId('TicketPriority', 2),
              name: '2 normal',
              uiColor: null,
            },
            createdAt: '2025-02-20T10:21:14Z',
            __typename: 'Ticket', // If you remove this line the test will fail since it could be of any other entity type
          },
        ],
      },
    })
    const { wrapper } = renderSearchContent()

    await wrapper.events.type(
      wrapper.getByRole('searchbox', { name: 'Search…' }),
      '123',
    )

    const breadcrumbs = wrapper.getByRole('navigation', {
      name: 'Breadcrumb navigation',
    })

    expect(
      within(breadcrumbs).getByRole('heading', { name: 'Results', level: 1 }),
    ).toBeInTheDocument()

    expect(within(breadcrumbs).getByText('Search')).toBeInTheDocument()

    await waitFor(() => expect(breadcrumbs).toHaveTextContent('SearchResults1'))
  })

  it('displays a list of ticket entity search results', async () => {
    mockDetailSearchQuery({
      search: {
        totalCount: 0,
        items: [
          {
            id: convertToGraphQLId('Ticket', 469),
            internalId: 469,
            title: 'Foot ticket title',
            number: '12468',
            customer: {
              id: convertToGraphQLId('User', 2),
              fullname: 'Nicole Braun User',
            },
            group: {
              id: convertToGraphQLId('Group', 6),
              name: 'Group 1',
            },
            state: {
              id: convertToGraphQLId('State', 2),
              name: 'open',
            },
            stateColorCode: EnumTicketStateColorCode.Open,
            priority: {
              id: convertToGraphQLId('TicketPriority', 2),
              name: '2 normal',
              uiColor: null,
            },
            createdAt: '2025-02-20T10:21:14Z',
            __typename: 'Ticket', // If you remove this line the test will fail since it could be of any other entity type
          },
        ],
      },
    })

    const { wrapper } = renderSearchContent()

    await wrapper.events.type(
      wrapper.getByRole('searchbox', { name: 'Search…' }),
      'Foo ticke title',
    )

    const table = await wrapper.findByRole('table', {
      name: 'Search result for: Ticket',
    })

    expect(
      within(table).getByRole('link', { name: '12468' }),
    ).toBeInTheDocument()

    // exact table output is tested within entity list component
  })

  it('syncs entity with query param', async () => {
    const { wrapper } = renderSearchContent()

    await getTestRouter().push('/search/foo-bar')

    await waitFor(() =>
      expect(wrapper.getByRole('searchbox')).toHaveDisplayValue('foo-bar'),
    )
  })

  it('displays result counts', async () => {
    mockPermissions(['ticket.agent'])

    mockDetailSearchQuery({
      search: {
        totalCount: 2,
        items: [
          {
            id: convertToGraphQLId('Ticket', 469),
            internalId: 469,
            title: 'Foot ticket title',
            number: '12468',
            customer: {
              id: convertToGraphQLId('User', 2),
              fullname: 'Nicole Braun User',
            },
            group: {
              id: convertToGraphQLId('Group', 6),
              name: 'Group 1',
            },
            state: {
              id: convertToGraphQLId('State', 2),
              name: 'open',
            },
            stateColorCode: EnumTicketStateColorCode.Open,
            priority: {
              id: convertToGraphQLId('TicketPriority', 2),
              name: '2 normal',
              uiColor: null,
            },
            createdAt: '2025-02-20T10:21:14Z',
            __typename: 'Ticket', // If you remove this line the test will fail since it could be of any other entity type
          },
          {
            id: convertToGraphQLId('Ticket', 470),
            internalId: 470,
            title: 'Foot ticket title B',
            number: '12469',
            customer: {
              id: convertToGraphQLId('User', 2),
              fullname: 'Nicole Braun User',
            },
            group: {
              id: convertToGraphQLId('Group', 6),
              name: 'Group 1',
            },
            state: {
              id: convertToGraphQLId('State', 2),
              name: 'open',
            },
            stateColorCode: EnumTicketStateColorCode.Open,
            priority: {
              id: convertToGraphQLId('TicketPriority', 2),
              name: '2 normal',
              uiColor: null,
            },
            createdAt: '2025-02-20T10:21:14Z',
            __typename: 'Ticket', // If you remove this line the test will fail since it could be of any other entity type
          },
        ],
      },
    })
    const { wrapper } = renderSearchContent()

    // one in the breadcrumb one in the navigation tab
    await waitFor(() => expect(wrapper.getAllByText('2')).toHaveLength(2))
  })

  it('displays default empty message', async () => {
    mockDetailSearchQuery({
      search: {
        totalCount: 0,
        items: [],
      },
    })

    const { wrapper } = renderSearchContent()

    expect(
      await wrapper.findByText('No search results for this query.'),
    ).toBeInTheDocument()
  })

  it('displays all entity entries counts for an agent', async () => {
    mockPermissions(['ticket.agent'])

    mockDetailSearchQuery({
      search: {
        totalCount: 0,
        items: [],
      },
    })

    mockSearchCountsQuery({
      searchCounts: [
        {
          model: EnumSearchableModels.Organization,
          totalCount: 100,
        },
        {
          model: EnumSearchableModels.User,
          totalCount: 250,
        },
      ],
    })

    const { wrapper } = renderSearchContent()

    await wrapper.events.type(
      wrapper.getByRole('searchbox', { name: 'Search…' }),
      '123',
    )

    await Promise.all([
      waitForSearchCountsQueryCalls(),
      waitForDetailSearchQueryCalls(),
    ])

    expect(wrapper.getByRole('tab', { name: 'Organization 100' }))
    expect(wrapper.getByRole('tab', { name: 'User 250' }))
    expect(wrapper.getByRole('tab', { name: 'Ticket 0' }))
  })

  it('allows sorting of search results', async () => {
    mockDetailSearchQuery({
      search: {
        totalCount: 0,
        items: [
          {
            id: convertToGraphQLId('Ticket', 469),
            internalId: 469,
            title: 'Foot ticket title',
            number: '12468',
            customer: {
              id: convertToGraphQLId('User', 2),
              fullname: 'Nicole Braun User',
            },
            group: {
              id: convertToGraphQLId('Group', 6),
              name: 'Group 1',
            },
            state: {
              id: convertToGraphQLId('State', 2),
              name: 'open',
            },
            stateColorCode: EnumTicketStateColorCode.Open,
            priority: {
              id: convertToGraphQLId('TicketPriority', 2),
              name: '2 normal',
              uiColor: null,
            },
            createdAt: '2025-02-20T10:21:14Z',
            __typename: 'Ticket', // If you remove this line the test will fail since it could be of any other entity type
          },
        ],
      },
    })

    const { wrapper } = renderSearchContent()

    await wrapper.events.type(
      wrapper.getByRole('searchbox', { name: 'Search…' }),
      'Foo ticke title',
    )

    await waitForDetailSearchQueryCalls()

    await wrapper.events.click(
      wrapper.getAllByRole('button', { name: 'Sorted descending' })[0],
    )

    const mocks = await waitForDetailSearchQueryCalls()

    expect(mocks[1].variables.orderDirection).toBe('ASCENDING')
  })
})
