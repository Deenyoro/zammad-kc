// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { renderComponent } from '#tests/support/components/index.ts'
import { waitForNextTick } from '#tests/support/utils.ts'

import LayoutPage from '#desktop/components/layout/LayoutPage.vue'

import '#tests/graphql/builders/mocks.ts'

describe('LayoutPage', () => {
  it('expands search and focus quick search input', async () => {
    const wrapper = renderComponent(LayoutPage, { router: true })

    await wrapper.events.click(
      wrapper.getByRole('button', {
        name: 'Collapse sidebar',
      }),
    )

    expect(
      wrapper.queryByRole('searchbox', {
        name: 'Search…',
      }),
    ).not.toBeInTheDocument()

    await wrapper.events.click(
      wrapper.getByRole('button', {
        name: 'Open quick search',
      }),
    )

    await waitForNextTick()

    expect(
      wrapper.getByRole('searchbox', {
        name: 'Search…',
      }),
    ).toHaveFocus()
  })
})
