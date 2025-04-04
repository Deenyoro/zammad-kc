// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { storeToRefs } from 'pinia'
import { ref } from 'vue'

import renderComponent from '#tests/support/components/renderComponent.ts'
import { mockApplicationConfig } from '#tests/support/mock-applicationConfig.ts'
import { mockPermissions } from '#tests/support/mock-permissions.ts'

import { createDummyTicket } from '#shared/entities/ticket-article/__tests__/mocks/ticket.ts'
import { convertToGraphQLId } from '#shared/graphql/utils.ts'
import { useSessionStore } from '#shared/stores/session.ts'

import TicketSummaryBanner from '#desktop/pages/ticket/components/TicketDetailView/TicketSummaryBanner.vue'
import { TICKET_KEY } from '#desktop/pages/ticket/composables/useTicketInformation.ts'
import { TICKET_SIDEBAR_SYMBOL } from '#desktop/pages/ticket/composables/useTicketSidebar.ts'

const switchSidebar = vi.fn()

const renderTicketSummaryBanner = (ticket = createDummyTicket()) =>
  renderComponent(TicketSummaryBanner, {
    store: true,
    dialog: true,
    provide: [
      [
        TICKET_SIDEBAR_SYMBOL,
        {
          switchSidebar,
        },
      ],
      [TICKET_KEY, { ticket: ref(ticket) }],
    ],
  })

const mockCurrentUserPreference = (active: boolean) => {
  const { user } = storeToRefs(useSessionStore())
  // User query doesn't run, hence we manually mock store
  if (!user.value) {
    // eslint-disable-next-line @typescript-eslint/ban-ts-comment
    // @ts-expect-error
    user.value = {
      preferences: {
        ticket_summary_banner_hidden: active,
        ai_assistance_ticket_summary: true,
        ai_assistance_ticket_summary_config: {
          conversation_summary: true,
          open_questions: true,
          problem: true,
          suggestions: true,
        },
      },
    }
  }
}

describe('TicketSummaryBanner', () => {
  it('renders correctly', () => {
    mockApplicationConfig({
      ai_provider: 'zammad_ai',
      ai_assistance_ticket_summary: true,
      ai_assistance_ticket_summary_config: {
        conversation_summary: true,
        open_questions: true,
        problem: true,
        suggestions: true,
      },
    })

    const wrapper = renderTicketSummaryBanner()

    mockCurrentUserPreference(true)

    expect(wrapper.getByText('Zammad Smart Assist')).toBeInTheDocument()

    expect(
      wrapper.getByText('has prepared a summary of this ticket.'),
    ).toBeInTheDocument()

    expect(wrapper.getByIconName('smart-assist')).toBeInTheDocument()
  })

  it('shows summary sidebar when clicked', async () => {
    mockApplicationConfig({
      ai_provider: 'zammad_ai',
      ai_assistance_ticket_summary: true,
      ai_assistance_ticket_summary_config: {
        conversation_summary: true,
        open_questions: true,
        problem: true,
        suggestions: true,
      },
    })

    const wrapper = renderTicketSummaryBanner()

    mockCurrentUserPreference(true)

    await wrapper.events.click(
      wrapper.getByRole('button', { name: 'See Summary' }),
    )

    expect(switchSidebar).toHaveBeenCalledWith('ticket-summary')
  })

  it('hides banner if ticket has merged state', () => {
    mockApplicationConfig({
      ai_assistance_ticket_summary: true,
      ai_assistance_ticket_summary_config: {
        conversation_summary: true,
        open_questions: true,
        problem: true,
        suggestions: true,
      },
    })

    const wrapper = renderTicketSummaryBanner(
      createDummyTicket({
        state: {
          name: 'merged',
          id: convertToGraphQLId('State', 5),
          stateType: {
            id: convertToGraphQLId('StateType', 6),
            name: 'merged',
          },
        },
      }),
    )

    expect(wrapper.baseElement.firstChild).toBeEmptyDOMElement()
  })

  it('hides banner if feature is disabled', () => {
    mockApplicationConfig({
      ai_assistance_ticket_summary: false,
    })

    const wrapper = renderTicketSummaryBanner()

    expect(wrapper.baseElement.firstChild).toBeEmptyDOMElement()
  })

  it('hides banner if user is customer', () => {
    mockApplicationConfig({
      ai_assistance_ticket_summary: true,
    })

    mockPermissions(['ticket.agent'])

    const wrapper = renderTicketSummaryBanner()

    expect(wrapper.baseElement.firstChild).toBeEmptyDOMElement()
  })

  it('hides banner if provider is not available', () => {
    mockApplicationConfig({
      ai_provider: '',
    })

    mockPermissions(['ticket.agent'])

    const wrapper = renderTicketSummaryBanner()

    expect(wrapper.baseElement.firstChild).toBeEmptyDOMElement()
  })
})
