// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { beforeEach, describe, expect } from 'vitest'
import { useTemplateRef } from 'vue'

import { renderComponent } from '#tests/support/components/index.ts'
import { mockApplicationConfig } from '#tests/support/mock-applicationConfig.ts'

import { provideTicketInformationMocks } from '#desktop/entities/ticket/__tests__/mocks/provideTicketInformationMocks.ts'
import { testOptionsTopBar } from '#desktop/pages/ticket/components/TicketDetailView/TicketDetailTopBar/__tests__/support/testOptions.ts'
import TicketDetailTopBar from '#desktop/pages/ticket/components/TicketDetailView/TicketDetailTopBar/TicketDetailTopBar.vue'
import { mockChecklistTemplatesQuery } from '#desktop/pages/ticket/graphql/queries/checklistTemplates.mocks.ts'

const copyToClipboardMock = vi.fn()

vi.mock('#shared/composables/useCopyToClipboard.ts', async () => ({
  useCopyToClipboard: () => ({ copyToClipboard: copyToClipboardMock }),
}))

vi.mock('#desktop/pages/ticket/composables/useTicketSidebar.ts')

const renderTopBar = (options = testOptionsTopBar) => {
  return renderComponent(
    {
      components: { TicketDetailTopBar },
      setup() {
        provideTicketInformationMocks(options)
        const parentElement = useTemplateRef('parent')
        return { parentElement }
      },
      template: `<div ref="parent"><TicketDetailTopBar :content-container-element="parentElement"  /></div>`,
    },
    { form: true, router: true },
  )
}
describe('TicketDetailTopBar', () => {
  beforeEach(() => {
    mockApplicationConfig({
      fqdn: 'zammad.example.com',
      http_type: 'http',
      ticket_hook: 'Ticket#',
    })

    mockChecklistTemplatesQuery({
      checklistTemplates: [],
    })
  })

  it('shows breadcrumb with copyable ticket number', () => {
    const wrapper = renderTopBar()

    expect(wrapper.getByText('Ticket#89001')).toBeInTheDocument()
  })

  describe('features', () => {
    it('copies ticket number', async () => {
      const wrapper = renderTopBar()

      await wrapper.events.click(wrapper.getByIconName('files'))

      expect(copyToClipboardMock).toHaveBeenCalledWith([
        {
          data: {
            'text/html': '<a href="http://zammad.example.com/desktop/tickets/1">Ticket#89001</a>',
            'text/plain': 'Ticket#89001',
          },
          options: {
            presentationStyle: 'unspecified',
          },
        },
      ])
    })

    it('shows highlight menu', () => {
      const wrapper = renderTopBar()

      expect(wrapper.getByText('Highlight')).toBeInTheDocument()
      expect(wrapper.getByIconName('highlighter')).toBeInTheDocument()
    })
  })

  it('displays in readonly mode if update permission is not granted', () => {
    const readOnlyOptions = { ...testOptionsTopBar }
    testOptionsTopBar.policy.update = false

    const wrapper = renderTopBar(readOnlyOptions)

    expect(wrapper.queryByText('Highlight')).not.toBeInTheDocument()
    expect(wrapper.queryByRole('button', { name: 'Welcome to Zammad!' })).not.toBeInTheDocument()

    expect(
      wrapper.getByRole('heading', { name: 'Welcome to Zammad!', level: 2 }),
    ).toBeInTheDocument()
  })
})
