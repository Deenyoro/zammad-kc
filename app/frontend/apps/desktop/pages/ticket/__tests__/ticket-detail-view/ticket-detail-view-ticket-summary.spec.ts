// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { waitFor, within } from '@testing-library/vue'

import { visitView } from '#tests/support/components/visitView.ts'
import { mockApplicationConfig } from '#tests/support/mock-applicationConfig.ts'
import { mockPermissions } from '#tests/support/mock-permissions.ts'
import { waitForNextTick } from '#tests/support/utils.ts'

import { mockTicketQuery } from '#shared/entities/ticket/graphql/queries/ticket.mocks.ts'
import { getTicketArticleUpdatesSubscriptionHandler } from '#shared/entities/ticket/graphql/subscriptions/ticketArticlesUpdates.mocks.ts'
import { createDummyTicket } from '#shared/entities/ticket-article/__tests__/mocks/ticket.ts'
import {
  EnumTicketArticleSenderName,
  type TicketAiAssistanceSummaryUpdatesPayload,
  type TicketArticleUpdatesPayload,
} from '#shared/graphql/types.ts'
import { convertToGraphQLId } from '#shared/graphql/utils.ts'

import { waitForUserCurrentTicketSummaryBannerHiddenMutationCalls } from '#desktop/entities/user/current/graphql/mutations/userCurrentTicketSummaryBannerHidden.mocks.ts'
import {
  mockTicketAiAssistanceSummarizeMutation,
  waitForTicketAiAssistanceSummarizeMutationCalls,
} from '#desktop/pages/ticket/graphql/mutations/ticketAIAssistanceSummarize.mocks.ts'
import { getTicketAiAssistanceSummaryUpdatesSubscriptionHandler } from '#desktop/pages/ticket/graphql/subscriptions/ticketAIAssistanceSummaryUpdates.mocks.ts'

import type { DeepPartial } from '@apollo/client/utilities'

const triggerSummaryUpdate = async (
  data: TicketAiAssistanceSummaryUpdatesPayload,
  withInitialSubscription = true,
) => {
  const mockSubscription = getTicketAiAssistanceSummaryUpdatesSubscriptionHandler()

  if (withInitialSubscription) {
    await mockSubscription.trigger({
      ticketAIAssistanceSummaryUpdates: {
        summary: null,
        error: null,
      },
    })
  }

  await mockSubscription.trigger({
    ticketAIAssistanceSummaryUpdates: data,
  })
}

const triggerArticleUpdate = async (
  data: DeepPartial<TicketArticleUpdatesPayload>,
  withInitialSubscription = true,
) => {
  const mockSubscription = await getTicketArticleUpdatesSubscriptionHandler()

  if (withInitialSubscription) {
    await mockSubscription.trigger({
      ticketArticleUpdates: {
        addArticle: null,
        updateArticle: null,
        removeArticleId: null,
      },
    })
  }

  await waitForNextTick()

  await mockSubscription.trigger({
    ticketArticleUpdates: data,
  })
}

describe('Ticket detail view - Ticket summary', () => {
  it('shows ticket summary to agent', async () => {
    mockPermissions(['ticket.agent'])

    mockTicketQuery({
      ticket: createDummyTicket(),
    })

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

    mockTicketAiAssistanceSummarizeMutation({
      ticketAIAssistanceSummarize: {
        summary: {
          conversationSummary:
            'The customer paid for an order but claims to have not received it. They provided the order number and requested assistance with tracking.',
          openQuestions: ['What was the payment method used?'],
          problem: 'Order not received after payment',
          suggestions: [
            'Check the order status in the system',
            'Verify if the shipping address is correct',
            'Contact the shipping carrier for updates',
          ],
        },
      },
    })

    const view = await visitView('/tickets/1')

    const contentSidebar = await view.findByRole('complementary', {
      name: 'Content sidebar',
    })

    expect(within(contentSidebar).getByRole('button', { name: 'Summary' })).toBeInTheDocument()

    await view.events.click(within(contentSidebar).getByRole('button', { name: 'Summary' }))

    expect(
      await within(contentSidebar).findByRole('heading', {
        name: 'Customer Intent',
        level: 3,
      }),
    ).toBeInTheDocument()
  })

  it('hides ticket summary for customer', async () => {
    mockPermissions(['ticket.customer'])

    mockTicketQuery({
      ticket: createDummyTicket(),
    })

    const view = await visitView('/tickets/1')

    const contentSidebar = view.getByRole('complementary', {
      name: 'Content sidebar',
    })

    expect(
      within(contentSidebar).queryByRole('button', { name: 'Summary' }),
    ).not.toBeInTheDocument()
  })

  it('re-invokes summary update when new article is created', async () => {
    mockPermissions(['ticket.agent'])

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

    mockTicketQuery({
      ticket: createDummyTicket(),
    })

    const view = await visitView('/tickets/1')

    await view.events.click(view.getByRole('button', { name: 'Summary' }))

    const calls = await waitForTicketAiAssistanceSummarizeMutationCalls()

    expect(calls).toHaveLength(1)

    expect(await view.findByRole('heading', { name: 'Customer Intent' }))

    await triggerArticleUpdate({
      addArticle: {
        createdAt: new Date().toISOString(),
        sender: {
          name: EnumTicketArticleSenderName.Customer,
        },
        id: convertToGraphQLId('Article', 1),
      },
      updateArticle: null,
      removeArticleId: null,
    })

    expect(calls).toHaveLength(2)
  })

  it('does not re-invoke summary update when article of type system is updated', async () => {
    mockPermissions(['ticket.agent'])

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

    mockTicketQuery({
      ticket: createDummyTicket(),
    })

    const view = await visitView('/tickets/1')

    await view.events.click(view.getByRole('button', { name: 'Summary' }))

    const calls = await waitForTicketAiAssistanceSummarizeMutationCalls()

    expect(calls).toHaveLength(1)

    expect(await view.findByRole('heading', { name: 'Customer Intent' }))

    await triggerArticleUpdate(
      {
        addArticle: {
          sender: {
            name: EnumTicketArticleSenderName.System,
          },
        },
        updateArticle: null,
        removeArticleId: null,
      },
      false,
    )

    expect(calls).toHaveLength(1)
  })

  it('triggers summary update when subscription comes in', async () => {
    mockPermissions(['ticket.agent'])

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

    mockTicketAiAssistanceSummarizeMutation({
      ticketAIAssistanceSummarize: {
        summary: {
          conversationSummary:
            'The customer paid for an order but claims to have not received it. They provided the order number and requested assistance with tracking.',
          openQuestions: ['What was the payment method used?'],
          problem: 'Order not received after payment',
          suggestions: [
            'Check the order status in the system',
            'Verify if the shipping address is correct',
            'Contact the shipping carrier for updates',
          ],
        },
      },
    })

    const ticket = createDummyTicket()

    mockTicketQuery({
      ticket,
    })

    const view = await visitView('/tickets/1')

    await view.events.click(view.getByRole('button', { name: 'Summary' }))

    await triggerSummaryUpdate({
      summary: {
        conversationSummary: 'Summary to see if subscription comes in',
        openQuestions: ['...'],
        problem: '...',
        suggestions: ['foo', 'bar'],
      },
      error: null,
    })

    expect(
      await view.findByRole('heading', { level: 3, name: 'Customer Intent' }),
    ).toBeInTheDocument()

    expect(await view.findByText('Summary to see if subscription comes in')).toBeInTheDocument()
  })

  it('hides summary banner if user dismissed it', async () => {
    mockPermissions(['ticket.agent'])

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

    mockTicketAiAssistanceSummarizeMutation({
      ticketAIAssistanceSummarize: {
        summary: {
          conversationSummary:
            'The customer paid for an order but claims to have not received it. They provided the order number and requested assistance with tracking.',
          openQuestions: ['What was the payment method used?'],
          problem: 'Order not received after payment',
          suggestions: [
            'Check the order status in the system',
            'Verify if the shipping address is correct',
            'Contact the shipping carrier for updates',
          ],
        },
      },
    })

    const ticket = createDummyTicket()

    mockTicketQuery({
      ticket,
    })

    const view = await visitView('/tickets/1')

    await view.events.click(await view.findByRole('button', { name: 'Hide ticket summary banner' }))

    const dialog = await view.findByRole('dialog', {
      name: 'Hide Smart Assist Summary Banner?',
    })

    await view.events.click(within(dialog).getByRole('button', { name: 'Yes, hide it' }))

    const calls = await waitForUserCurrentTicketSummaryBannerHiddenMutationCalls()

    expect(calls.at(-1)?.variables).toEqual({ hidden: true })

    //  We have no cache in test environment
    // User subscription does not trigger
    // We could try to verify if banner is not shown anymore
  })

  it('displays update indicator when new summary comes in', async () => {
    mockPermissions(['ticket.agent'])

    mockApplicationConfig({
      ai_provider: 'zammad_ai',
      ai_assistance_ticket_summary: true,
    })

    mockTicketQuery({
      ticket: createDummyTicket(),
    })

    const view = await visitView('/tickets/1')

    await waitForTicketAiAssistanceSummarizeMutationCalls()

    expect(await view.findByRole('status', { name: 'Has update' })).toBeInTheDocument()
  })

  it('hides update indicator when ticket summary sidebar is opened', async () => {
    mockPermissions(['ticket.agent'])

    mockApplicationConfig({
      ai_provider: 'zammad_ai',
      ai_assistance_ticket_summary: true,
    })

    mockTicketQuery({
      ticket: createDummyTicket(),
    })

    const view = await visitView('/tickets/1')

    await waitForTicketAiAssistanceSummarizeMutationCalls()

    await view.events.click(view.getByRole('button', { name: 'Summary' }))

    expect(view.queryByRole('status', { name: 'Has update' })).not.toBeInTheDocument()
  })

  describe('errors', () => {
    beforeEach(() => {
      mockPermissions(['ticket.agent'])

      mockTicketQuery({
        ticket: createDummyTicket(),
      })
    })

    it('shows error message to agent if summary generation fails', async () => {
      mockTicketAiAssistanceSummarizeMutation({
        ticketAIAssistanceSummarize: {
          summary: null,
        },
      })
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

      const view = await visitView('/tickets/1')

      await view.events.click(view.getByRole('button', { name: 'Summary' }))

      await waitForTicketAiAssistanceSummarizeMutationCalls()

      await triggerSummaryUpdate({
        summary: null,
        error: {
          message: 'Authentication problem with provider.',
          exception: 'Error',
        },
      })

      expect(
        view.getByText(
          'The summary could not be generated. Please try again later or contact your administrator.',
        ),
      ).toBeInTheDocument()
    })

    it('shows specific error message to admin', async () => {
      mockPermissions(['ticket.agent', 'admin'])

      mockTicketAiAssistanceSummarizeMutation({
        ticketAIAssistanceSummarize: {
          summary: null,
        },
      })

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

      const view = await visitView('/tickets/1')

      await view.events.click(view.getByRole('button', { name: 'Summary' }))

      await waitForTicketAiAssistanceSummarizeMutationCalls()

      await triggerSummaryUpdate({
        summary: null,
        error: {
          message: 'Authentication problem with provider.',
          exception: 'Error',
        },
      })

      expect(view.getByText('Authentication problem with provider.')).toBeInTheDocument()
    })

    it('shows no ai provider is selected', async () => {
      mockApplicationConfig({
        ai_provider: '',
        ai_assistance_ticket_summary: true,
        ai_assistance_ticket_summary_config: {
          conversation_summary: true,
          open_questions: true,
          problem: true,
          suggestions: true,
        },
      })

      const view = await visitView('/tickets/1')

      await view.events.click(view.getByRole('button', { name: 'Summary' }))

      expect(
        view.getByText('No AI provider is currently set up. Please contact your administrator.'),
      ).toBeInTheDocument()
    })
  })

  it('hides sidebar when feature is disabled', async () => {
    mockPermissions(['ticket.agent'])

    mockApplicationConfig({
      ai_provider: 'zammad_ai',
      ai_assistance_ticket_summary: false,
    })

    mockTicketQuery({
      ticket: createDummyTicket(),
    })

    const view = await visitView('/tickets/1')

    expect(view.queryByRole('button', { name: 'Summary' })).not.toBeInTheDocument()
  })

  describe('ticket summary banner', () => {
    it('renders correctly', async () => {
      mockPermissions(['ticket.agent'])

      mockApplicationConfig({
        ai_provider: 'zammad_ai',
        ai_assistance_ticket_summary: true,
      })

      mockTicketQuery({
        ticket: createDummyTicket(),
      })

      const view = await visitView('/tickets/1')

      await getTicketAiAssistanceSummaryUpdatesSubscriptionHandler().trigger({
        ticketAIAssistanceSummaryUpdates: {
          summary: null,
          error: null,
        },
      })

      expect(await view.findByTestId('ticket-summary-banner')).toHaveTextContent(
        'Zammad Smart Assist ticket summary has been generated.',
      )

      expect(view.getAllByIconName('smart-assist').length).toBe(2)
    })

    it('shows summary sidebar when clicked', async () => {
      mockPermissions(['ticket.agent'])

      mockApplicationConfig({
        ai_provider: 'zammad_ai',
        ai_assistance_ticket_summary: true,
      })

      mockTicketQuery({
        ticket: createDummyTicket(),
      })

      const view = await visitView('/tickets/1')

      await view.events.click(await view.findByRole('button', { name: 'See Summary' }))

      expect(
        await view.findByRole('complementary', { name: 'Content sidebar' }),
      ).toBeInTheDocument()
    })

    it('hides banner if ticket has merged state', async () => {
      mockPermissions(['ticket.agent'])

      mockApplicationConfig({
        ai_provider: 'zammad_ai',
        ai_assistance_ticket_summary: true,
      })

      mockTicketQuery({
        ticket: createDummyTicket({
          state: {
            name: 'merged',
            id: convertToGraphQLId('State', 5),
            stateType: {
              id: convertToGraphQLId('StateType', 6),
              name: 'merged',
            },
          },
        }),
      })

      const view = await visitView('/tickets/1')

      expect(view.queryByRole('button', { name: 'See Summary' })).not.toBeInTheDocument()
    })

    it('hides banner if feature is disabled', async () => {
      mockPermissions(['ticket.agent'])

      mockTicketQuery({
        ticket: createDummyTicket(),
      })

      mockApplicationConfig({
        ai_provider: 'zammad_ai',
        ai_assistance_ticket_summary: false,
      })

      const view = await visitView('/tickets/1')

      expect(view.queryByRole('button', { name: 'See Summary' })).not.toBeInTheDocument()
    })

    it('hides banner if user is customer', async () => {
      mockPermissions(['ticket.customer'])

      mockTicketQuery({
        ticket: createDummyTicket(),
      })

      mockApplicationConfig({
        ai_provider: 'zammad_ai',
        ai_assistance_ticket_summary: true,
      })

      const view = await visitView('/tickets/1')

      expect(view.queryByRole('button', { name: 'See Summary' })).not.toBeInTheDocument()
    })

    it('hides banner if provider is not available', async () => {
      mockPermissions(['ticket.agent'])

      mockTicketQuery({
        ticket: createDummyTicket(),
      })

      mockApplicationConfig({
        ai_provider: '',
      })

      const view = await visitView('/tickets/1')

      expect(view.queryByRole('button', { name: 'See Summary' })).not.toBeInTheDocument()
    })

    it('hides banner if ticket summary tab is active', async () => {
      mockPermissions(['ticket.agent'])

      mockTicketQuery({
        ticket: createDummyTicket(),
      })

      mockApplicationConfig({
        ai_provider: 'zammad_ai',
        ai_assistance_ticket_summary: true,
      })

      const ticket = createDummyTicket()

      mockTicketQuery({ ticket })

      const view = await visitView('/tickets/1')

      await view.events.click(await view.findByRole('button', { name: 'See Summary' }))

      expect(view.queryByRole('button', { name: 'See Summary' })).not.toBeInTheDocument()
    })
  })

  it('hides ticket summary banner when user is on ticket summary sidebar tab', async () => {
    mockPermissions(['ticket.agent'])

    mockApplicationConfig({
      ai_provider: 'zammad_ai',
      ai_assistance_ticket_summary: true,
    })

    mockTicketQuery({
      ticket: createDummyTicket(),
    })

    const view = await visitView('/tickets/1')

    await view.events.click(await view.findByRole('button', { name: 'See Summary' }))

    expect(view.queryByRole('button', { name: 'See Summary' })).not.toBeInTheDocument()
  })

  it('shows ticket summary is progressing in banner', async () => {
    mockPermissions(['ticket.agent'])

    mockApplicationConfig({
      ai_provider: 'zammad_ai',
      ai_assistance_ticket_summary: true,
    })

    mockTicketQuery({
      ticket: createDummyTicket(),
    })

    const view = await visitView('/tickets/1')

    await waitForNextTick()

    expect(view.getByTestId('ticket-summary-banner')).toHaveTextContent(
      'Zammad Smart Assist is preparing summary…See Summary',
    )
  })

  it('shows ticket summary banner when subscription update comes in', async () => {
    mockPermissions(['ticket.agent'])

    mockApplicationConfig({
      ai_provider: 'zammad_ai',
      ai_assistance_ticket_summary: true,
    })

    mockTicketQuery({
      ticket: createDummyTicket(),
    })

    mockTicketAiAssistanceSummarizeMutation({
      ticketAIAssistanceSummarize: {
        summary: {
          conversationSummary:
            'The customer paid for an order but claims to have not received it. They provided the order number and requested assistance with tracking.',
          openQuestions: ['What was the payment method used?'],
          problem: 'Order not received after payment',
          suggestions: [
            'Check the order status in the system',
            'Verify if the shipping address is correct',
            'Contact the shipping carrier for updates',
          ],
        },
        fingerprintMd5: '5987df7488e9d904519cdc6235c9dc39',
      },
    })

    const view = await visitView('/tickets/1')

    await view.events.click(await view.findByRole('button', { name: 'See Summary' }))

    await waitForTicketAiAssistanceSummarizeMutationCalls()

    await waitForNextTick()

    await triggerSummaryUpdate({
      summary: null,
      error: null,
    })

    await waitFor(() =>
      expect(view.queryByRole('button', { name: 'See Summary' })).toBeInTheDocument(),
    )
  })

  it('displays ticket summary banner when subscription update comes in', async () => {
    mockPermissions(['ticket.agent'])

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

    mockTicketAiAssistanceSummarizeMutation({
      ticketAIAssistanceSummarize: {
        summary: {
          conversationSummary:
            'The customer paid for an order but claims to have not received it. They provided the order number and requested assistance with tracking.',
          openQuestions: ['What was the payment method used?'],
          problem: 'Order not received after payment',
          suggestions: [
            'Check the order status in the system',
            'Verify if the shipping address is correct',
            'Contact the shipping carrier for updates',
          ],
        },
        fingerprintMd5: '5987df7488e9d904519cdc6235c9dc32',
      },
    })

    mockTicketQuery({
      ticket: createDummyTicket(),
    })

    const view = await visitView('/tickets/1')

    await view.events.click(await view.findByRole('button', { name: 'See Summary' }))

    expect(view.queryByRole('button', { name: 'See Summary' })).not.toBeInTheDocument()

    // Change sidebar tab
    await view.events.click(await view.findByRole('button', { name: 'Ticket' }))

    await triggerSummaryUpdate({
      summary: {
        conversationSummary: 'Summary to see if subscription comes in',
        openQuestions: ['...'],
        problem: '...',
        suggestions: ['foo', 'bar'],
      },
      fingerprintMd5: '5987df7488e9d904519cdc6235c9dc39',
      error: null,
    })

    expect(await view.findByRole('button', { name: 'See Summary' })).toBeInTheDocument()
  })
})
