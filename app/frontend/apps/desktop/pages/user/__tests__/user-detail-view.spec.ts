// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { within } from '@testing-library/vue'

import { visitView } from '#tests/support/components/visitView.ts'
import { mockPermissions } from '#tests/support/mock-permissions.ts'

import { mockUserQuery } from '#shared/entities/user/graphql/queries/user.mocks.ts'

describe('User Detail View', () => {
  beforeEach(() => {
    mockPermissions(['ticket.agent'])

    mockUserQuery({
      user: {
        __typename: 'User',
        id: 'gid://zammad/User/2',
        internalId: 2,
        firstname: 'Nicole',
        lastname: 'Braun',
        fullname: 'Nicole Braun',
        email: 'nicole.braun@zammad.org',
        organization: {
          __typename: 'Organization',
          id: 'gid://zammad/Organization/1',
          internalId: 1,
          name: 'Zammad Foundation',
        },
        phone: '+49 123 4567890',
        mobile: '+49 987 6543210',
        image: null,
        vip: false,
        outOfOffice: false,
        outOfOfficeStartAt: null,
        outOfOfficeEndAt: null,
        active: true,
      },
    })
  })

  describe('Top information bar', () => {
    it('displays breadcrumb navigation', async () => {
      const view = await visitView('/users/2')

      const main = view.getByRole('main')
      const header = within(main).getByTestId('user-detail-top-bar')
      const breadcrumb = within(header).getByRole('navigation', { name: 'Breadcrumb navigation' })
      const items = within(breadcrumb).getAllByRole('listitem')

      expect(items).toHaveLength(2)
      expect(items[0]).toHaveTextContent('User')
      expect(within(items[1]).getByRole('heading')).toHaveAccessibleName('Nicole Braun')
    })

    it('displays basic user information', async () => {
      const view = await visitView('/users/2')

      const main = view.getByRole('main')
      const header = within(main).getByTestId('user-detail-top-bar')

      expect(within(header).getByLabelText('Avatar (Nicole Braun)')).toHaveTextContent('NB')
      expect(within(header).getByText('Nicole Braun', { selector: 'span' })).toBeVisible()
      expect(within(header).getByText('Zammad Foundation')).toBeVisible()
    })
  })

  describe('Object attributes', () => {
    it('displays user attributes', async () => {
      const view = await visitView('/users/2')

      const main = view.getByRole('main')

      expect(within(main).getByText('Email').parentElement).toHaveTextContent(
        'nicole.braun@zammad.org',
      )
      expect(within(main).getByText('Phone').parentElement).toHaveTextContent('+49 123 4567890')
      expect(within(main).getByText('Mobile').parentElement).toHaveTextContent('+49 987 6543210')
    })
  })
})
