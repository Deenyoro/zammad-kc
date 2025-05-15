// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { visitView } from '#tests/support/components/visitView.ts'
import { mockApplicationConfig } from '#tests/support/mock-applicationConfig.ts'
import { mockPermissions } from '#tests/support/mock-permissions.ts'
import { mockUserCurrent } from '#tests/support/mock-userCurrent.ts'
import { waitUntil } from '#tests/support/vitest-wrapper.ts'

import { EnumAppearanceTheme } from '#shared/graphql/types.ts'

import { waitForUserCurrentTicketSummaryBannerHiddenMutationCalls } from '#desktop/entities/user/current/graphql/mutations/userCurrentTicketSummaryBannerHidden.mocks.ts'
import { waitForUserCurrentAppearanceMutationCalls } from '#desktop/pages/personal-setting/graphql/mutations/userCurrentAppearance.mocks.ts'

describe('appearance page', () => {
  it('should have dark theme set', async () => {
    mockUserCurrent({
      preferences: {
        theme: EnumAppearanceTheme.Dark,
      },
    })

    const view = await visitView('/personal-setting/appearance')

    expect(view.getByRole('radio', { checked: true })).toHaveTextContent('dark')
  })

  it('should have light theme set', async () => {
    mockUserCurrent({
      preferences: {
        theme: EnumAppearanceTheme.Light,
      },
    })

    const view = await visitView('/personal-setting/appearance')

    expect(view.getByRole('radio', { checked: true })).toHaveTextContent(
      'light',
    )
  })

  it('update appearance to dark', async () => {
    mockUserCurrent({
      preferences: {
        theme: EnumAppearanceTheme.Light,
      },
    })
    const view = await visitView('/personal-setting/appearance')

    expect(view.getByLabelText('Light')).toBeChecked()

    const darkMode = view.getByText('Dark')
    const lightMode = view.getByText('Light')
    const syncWithComputer = view.getByText('Sync with computer')

    await view.events.click(darkMode)

    expect(view.getByLabelText('Dark')).toBeChecked()

    const calls = await waitForUserCurrentAppearanceMutationCalls()

    expect(calls.at(-1)?.variables).toEqual({ theme: 'dark' })
    expect(window.matchMedia('(prefers-color-scheme: light)').matches).toBe(
      false,
    )

    await view.events.click(lightMode)
    await waitUntil(() => calls.length === 2)

    expect(calls.at(-1)?.variables).toEqual({ theme: 'light' })
    expect(window.matchMedia('(prefers-color-scheme: dark)').matches).toBe(
      false,
    )

    await view.events.click(syncWithComputer)

    expect(view.getByLabelText('Sync with computer')).toBeChecked()
  })

  it('shows display setting for ticket summary banner', async () => {
    mockPermissions(['ticket.agent'])

    mockApplicationConfig({
      ai_provider: 'ZammadAI',
      ai_assistance_ticket_summary: true,
    })

    // :TODO add assertion for ticket summary banner as soon as available
    mockUserCurrent({
      preferences: {
        ticket_summary_banner: true,
      },
    })

    const view = await visitView('/personal-setting/appearance')

    expect(
      await view.findByRole('heading', { level: 3, name: 'Ticket Summary' }),
    ).toBeInTheDocument()
  })

  it('hides display setting for ticket summary banner', async () => {
    mockApplicationConfig({
      ai_provider: 'zammad_ai',
      ai_assistance_ticket_summary: false,
    })

    const view = await visitView('/personal-setting/appearance')

    expect(
      view.queryByRole('heading', { level: 3, name: 'Ticket Summary' }),
    ).not.toBeInTheDocument()
  })

  it('update display setting for ticket summary banner', async () => {
    mockApplicationConfig({
      ai_provider: 'ZammadAI',
      ai_assistance_ticket_summary: true,
    })

    mockApplicationConfig({
      ticket_summary_banner: false,
    })

    const view = await visitView('/personal-setting/appearance')

    await view.events.click(
      view.getByRole('checkbox', {
        name: 'Disable the banner for the ticket summary smart assist',
      }),
    )

    const calls =
      await waitForUserCurrentTicketSummaryBannerHiddenMutationCalls()

    expect(calls.at(-1)?.variables).toEqual({
      hidden: true,
    })
  })

  it('hides display setting for ticket summary banner if provider is not set', async () => {
    mockApplicationConfig({
      ai_provider: '',
      ai_assistance_ticket_summary: true,
    })

    const view = await visitView('/personal-setting/appearance')

    expect(
      view.queryByRole('heading', { level: 3, name: 'Ticket Summary' }),
    ).not.toBeInTheDocument()
  })
})
