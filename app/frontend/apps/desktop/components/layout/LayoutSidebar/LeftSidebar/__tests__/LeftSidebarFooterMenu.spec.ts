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

    expect(view.getByText('New BETA UI')).toBeInTheDocument()
  })
})
