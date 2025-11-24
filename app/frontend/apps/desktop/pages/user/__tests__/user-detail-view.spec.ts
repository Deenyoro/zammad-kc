// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { waitFor, within } from '@testing-library/vue'

import { visitView } from '#tests/support/components/visitView.ts'
import { mockApplicationConfig } from '#tests/support/mock-applicationConfig.ts'
import { mockPermissions } from '#tests/support/mock-permissions.ts'

import { mockUserQuery } from '#shared/entities/user/graphql/queries/user.mocks.ts'
import type { OrganizationEdge, User } from '#shared/graphql/types.ts'

const copyToClipboardMock = vi.fn()

vi.mock('#shared/composables/useCopyToClipboard.ts', async () => ({
  useCopyToClipboard: () => ({ copyToClipboard: copyToClipboardMock }),
}))

const user: User = {
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
    active: true,
    policy: {
      update: true,
      destroy: true,
    },
    createdAt: '2020-01-01T12:00:00Z',
    updatedAt: '2020-01-01T12:00:00Z',
  },
  phone: '+49 123 4567890',
  mobile: '+49 987 6543210',
  image: null,
  vip: false,
  outOfOffice: false,
  outOfOfficeStartAt: null,
  outOfOfficeEndAt: null,
  hasSecondaryOrganizations: false,
  active: true,
  policy: {
    update: true,
    destroy: true,
  },
  createdAt: '2020-01-01T12:00:00Z',
  updatedAt: '2020-01-01T12:00:00Z',
}

const secondaryOrganizationEdges: OrganizationEdge[] = [
  {
    __typename: 'OrganizationEdge',
    node: {
      __typename: 'Organization',
      id: 'gid://zammad/Organization/2',
      internalId: 2,
      name: 'Secondary Org 1',
      active: true,
      policy: {
        update: true,
        destroy: true,
      },
      createdAt: '2020-01-02T12:00:00Z',
      updatedAt: '2020-01-02T12:00:00Z',
    },
    cursor: 'Mw',
  },
  {
    __typename: 'OrganizationEdge',
    node: {
      __typename: 'Organization',
      id: 'gid://zammad/Organization/3',
      internalId: 3,
      name: 'Secondary Org 2',
      active: true,
      policy: {
        update: true,
        destroy: true,
      },
      createdAt: '2020-01-02T12:00:00Z',
      updatedAt: '2020-01-02T12:00:00Z',
    },
    cursor: 'Mw',
  },
  {
    __typename: 'OrganizationEdge',
    node: {
      __typename: 'Organization',
      id: 'gid://zammad/Organization/4',
      internalId: 4,
      name: 'Secondary Org 3',
      active: true,
      policy: {
        update: true,
        destroy: true,
      },
      createdAt: '2020-01-02T12:00:00Z',
      updatedAt: '2020-01-02T12:00:00Z',
    },
    cursor: 'Mw',
  },
  {
    __typename: 'OrganizationEdge',
    node: {
      __typename: 'Organization',
      id: 'gid://zammad/Organization/5',
      internalId: 5,
      name: 'Secondary Org 4',
      active: true,
      policy: {
        update: true,
        destroy: true,
      },
      createdAt: '2020-01-02T12:00:00Z',
      updatedAt: '2020-01-02T12:00:00Z',
    },
    cursor: 'Mw',
  },
  {
    __typename: 'OrganizationEdge',
    node: {
      __typename: 'Organization',
      id: 'gid://zammad/Organization/6',
      internalId: 6,
      name: 'Secondary Org 5',
      active: true,
      policy: {
        update: true,
        destroy: true,
      },
      createdAt: '2020-01-02T12:00:00Z',
      updatedAt: '2020-01-02T12:00:00Z',
    },
    cursor: 'Mw',
  },
]

describe('User Detail View', () => {
  beforeEach(() => {
    mockApplicationConfig({
      fqdn: 'zammad.example.com',
      http_type: 'http',
    })

    mockPermissions(['ticket.agent'])
    mockUserQuery({ user })
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

    it('copies user name', async () => {
      const view = await visitView('/users/2')

      const main = view.getByRole('main')
      const header = within(main).getByTestId('user-detail-top-bar')
      const breadcrumb = within(header).getByRole('navigation', { name: 'Breadcrumb navigation' })

      await view.events.click(within(breadcrumb).getByRole('button', { name: 'Copy user name' }))

      expect(copyToClipboardMock).toHaveBeenCalledWith([
        {
          data: {
            'text/html': '<a href="http://zammad.example.com/desktop/users/2">Nicole Braun</a>',
            'text/plain': 'Nicole Braun',
          },
          options: {
            presentationStyle: 'unspecified',
          },
        },
      ])
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

  describe('Secondary organizations', () => {
    it('hides section when user has no secondary organizations', async () => {
      const view = await visitView('/users/2')

      const main = view.getByRole('main')

      expect(
        within(main).queryByRole('region', { name: 'Secondary organizations' }),
      ).not.toBeInTheDocument()
    })

    it('displays section when user has some secondary organizations', async () => {
      const userWithSecondaryOrganizations: User = {
        ...user,
        hasSecondaryOrganizations: true,
        secondaryOrganizations: {
          edges: secondaryOrganizationEdges.slice(0, 2),
          pageInfo: {
            endCursor: 'Mw',
            hasNextPage: false,
            hasPreviousPage: false,
          },
          totalCount: 2,
        },
      }

      mockUserQuery({ user: userWithSecondaryOrganizations })

      const view = await visitView('/users/2')

      const main = view.getByRole('main')

      const container = within(main).getByRole('region', { name: 'Secondary organizations' })

      expect(
        within(container).getByRole('heading', { name: 'Secondary organizations 2' }),
      ).toBeInTheDocument()

      waitFor(() => {
        expect(within(container).getByText('Secondary Org 1')).toBeInTheDocument()
        expect(within(container).getByText('Secondary Org 2')).toBeInTheDocument()
      })
    })

    it('supports fetching more secondary organizations', async () => {
      const userWithSecondaryOrganizations: User = {
        ...user,
        hasSecondaryOrganizations: true,
        secondaryOrganizations: {
          edges: secondaryOrganizationEdges.slice(0, 4),
          pageInfo: {
            endCursor: 'Mw',
            hasNextPage: true,
            hasPreviousPage: false,
          },
          totalCount: 5,
        },
      }

      mockUserQuery({ user: userWithSecondaryOrganizations })

      const view = await visitView('/users/2')

      const main = view.getByRole('main')

      const container = within(main).getByRole('region', { name: 'Secondary organizations' })

      expect(
        within(container).getByRole('heading', { name: 'Secondary organizations 5' }),
      ).toBeInTheDocument()

      waitFor(() => {
        expect(within(container).getByText('Secondary Org 1')).toBeInTheDocument()
        expect(within(container).getByText('Secondary Org 2')).toBeInTheDocument()
        expect(within(container).getByText('Secondary Org 3')).toBeInTheDocument()
        expect(within(container).getByText('Secondary Org 4')).toBeInTheDocument()

        expect(within(container).queryByText('Secondary Org 5')).not.toBeInTheDocument()

        expect(within(container).getByRole('button', { name: 'Show more' })).toBeInTheDocument()
      })

      mockUserQuery({
        user: {
          ...userWithSecondaryOrganizations,
          secondaryOrganizations: {
            edges: secondaryOrganizationEdges.slice(4),
            pageInfo: {
              endCursor: null,
            },
            totalCount: 5,
          },
        },
      })

      await view.events.click(within(container).getByRole('button', { name: 'Show more' }))

      waitFor(() => {
        expect(within(container).getByText('Secondary Org 1')).toBeInTheDocument()
        expect(within(container).getByText('Secondary Org 2')).toBeInTheDocument()
        expect(within(container).getByText('Secondary Org 3')).toBeInTheDocument()
        expect(within(container).getByText('Secondary Org 4')).toBeInTheDocument()
        expect(within(container).getByText('Secondary Org 5')).toBeInTheDocument()

        expect(
          within(container).queryByRole('button', { name: 'Show more' }),
        ).not.toBeInTheDocument()
      })
    })
  })
})
