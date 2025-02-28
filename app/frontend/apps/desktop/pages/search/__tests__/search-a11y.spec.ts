// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { axe } from 'vitest-axe'

import { visitView } from '#tests/support/components/visitView.ts'
import { mockPermissions } from '#tests/support/mock-permissions.ts'

import { convertToGraphQLId } from '#shared/graphql/utils.ts'

import { mockQuickSearchQuery } from '#desktop/components/Search/graphql/queries/quickSearch.mocks.ts'

describe('search view', () => {
  it('has no accessibility violations in main content', async () => {
    mockPermissions(['ticket.agent'])

    mockQuickSearchQuery({
      quickSearchOrganizations: {
        totalCount: 1,
        items: [
          {
            __typename: 'Organization',
            id: convertToGraphQLId('Organization', 1),
            internalId: 1,
            name: 'Organization 1',
          },
        ],
      },
      quickSearchUsers: {
        totalCount: 1,
        items: [
          {
            __typename: 'User',
            active: false,
            id: convertToGraphQLId('User', 1),
            internalId: 1,
            fullname: 'User',
          },
        ],
      },
      quickSearchTickets: {
        totalCount: 0,
        items: [],
      },
    })

    const view = await visitView('/search?search=test')

    const results = await axe(view.html())

    expect(results).toHaveNoViolations()
  })
})
