// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { renderComponent } from '#tests/support/components/index.ts'
import { mockApplicationConfig } from '#tests/support/mock-applicationConfig.ts'
import { mockUserCurrent } from '#tests/support/mock-userCurrent.ts'

import LeftSidebarFooterMenu from '../LeftSidebarFooterMenu.vue'

describe('layout sidebar footer menu', () => {
  beforeEach(() => {
    mockUserCurrent({
      lastname: 'Doe',
      firstname: 'John',
    })
  })

  it('renders user avatar', async () => {
    const view = renderComponent(LeftSidebarFooterMenu, {
      router: true,
      form: true,
    })

    expect(view.getByText('JD')).toBeInTheDocument()

    const avatar = view.getByTestId('common-avatar')
    expect(avatar).toHaveClass('size-normal')
  })

  it('renders small user avatar in collapsed mode', async () => {
    const view = renderComponent(LeftSidebarFooterMenu, {
      router: true,
      props: { collapsed: true },
    })

    expect(view.getByText('JD')).toBeInTheDocument()

    const avatar = view.getByTestId('common-avatar')
    expect(avatar).toHaveClass('size-small')
  })

  it('renders the beta UI switch (if enabled)', async () => {
    mockApplicationConfig({
      ui_desktop_beta_switch: true,
    })

    mockUserCurrent({
      hasBetaUiSwitchAvailable: true,
    })

    const view = renderComponent(LeftSidebarFooterMenu, {
      router: true,
      form: true,
    })

    expect(view.getByText('BETA UI')).toBeInTheDocument()
  })

  it('has no feedback link when the user is not in BETA program', async () => {
    mockApplicationConfig({
      ui_desktop_beta_switch: true,
    })

    mockUserCurrent({
      hasBetaUiSwitchAvailable: true,
    })

    const view = renderComponent(LeftSidebarFooterMenu, {
      router: true,
      form: true,
      dialog: true,
    })

    expect(view.queryByText('Feedback')).not.toBeInTheDocument()
  })

  it('opens manual feedback dialog', async () => {
    mockApplicationConfig({
      ui_desktop_beta_switch: true,
    })

    mockUserCurrent({
      hasBetaUiSwitchAvailable: true,
    })

    localStorage.setItem('beta-ui-switch', 'true')

    const view = renderComponent(LeftSidebarFooterMenu, {
      router: true,
      form: true,
      dialog: true,
    })

    const feedbackLink = view.getByText('Feedback')

    await view.events.click(feedbackLink)

    const feedbackDialog = await view.findByRole('dialog', { name: 'Send feedback on the BETA UI' })

    expect(feedbackDialog).toBeVisible()

    localStorage.removeItem('beta-ui-switch')
  })
})
