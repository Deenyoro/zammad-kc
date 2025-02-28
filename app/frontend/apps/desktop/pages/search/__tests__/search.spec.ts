// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { waitFor, within } from '@testing-library/vue'

import { visitView } from '#tests/support/components/visitView.ts'
import { mockPermissions } from '#tests/support/mock-permissions.ts'

const visitSearchView = async (searchTerm = 'test') => {
  const view = await visitView(`/search/${searchTerm}`)

  const searchContainer = view.getByTestId('search-container')

  return { view, searchContainer }
}

describe('search view', () => {
  it('renders view correctly', async () => {
    mockPermissions(['ticket.agent'])

    const { searchContainer } = await visitSearchView()

    expect(
      within(searchContainer).getByRole('searchbox', { name: 'Search…' }),
    ).toHaveDisplayValue('test')
  })

  it('write quick search input correctly to the search view input', async () => {
    mockPermissions(['ticket.agent'])

    const { searchContainer, view } = await visitSearchView()

    const primaryNavigationSidebar = view.getByRole('complementary', {
      name: 'Main sidebar',
    })

    const quickSearchInput = within(primaryNavigationSidebar).getByRole(
      'searchbox',
    )

    await view.events.type(quickSearchInput, 'fooBar')
    await view.events.keyboard('{Enter}')

    await waitFor(() =>
      expect(
        within(searchContainer).getByRole('searchbox', { name: 'Search…' }),
      ).toHaveDisplayValue('fooBar'),
    )
  })
})
