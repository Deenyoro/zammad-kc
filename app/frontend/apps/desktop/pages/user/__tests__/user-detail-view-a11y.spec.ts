// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { axe } from 'vitest-axe'

import { visitView } from '#tests/support/components/visitView.ts'
import { mockPermissions } from '#tests/support/mock-permissions.ts'

describe('User Detail View', () => {
  it('has no accessibility violations in main content', async () => {
    mockPermissions(['ticket.agent'])

    const view = await visitView('/users/2')

    const results = await axe(view.html())

    expect(results).toHaveNoViolations()
  })
})
