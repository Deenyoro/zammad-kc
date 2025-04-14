// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/
import { waitFor } from '@testing-library/vue'
import { ref, computed, effectScope } from 'vue'

import renderComponent from '#tests/support/components/renderComponent.ts'
import { mockApplicationConfig } from '#tests/support/mock-applicationConfig.ts'
import { mockRouterHooks } from '#tests/support/mock-vue-router.ts'

import type { TicketById } from '#shared/entities/ticket/types.ts'
import { createDummyArticle } from '#shared/entities/ticket-article/__tests__/mocks/ticket-articles.ts'
import { createDummyTicket } from '#shared/entities/ticket-article/__tests__/mocks/ticket.ts'
import { convertToGraphQLId } from '#shared/graphql/utils.ts'

import { pluginFiles } from '#desktop/pages/ticket/components/TicketSidebar/plugins/index.ts'
import plugin from '#desktop/pages/ticket/components/TicketSidebar/plugins/ticket-summary.ts'
import TicketSidebarSummary from '#desktop/pages/ticket/components/TicketSidebar/TicketSidebarSummary/TicketSidebarSummary.vue'
import { ARTICLES_INFORMATION_KEY } from '#desktop/pages/ticket/composables/useArticleContext.ts'
import { TICKET_KEY } from '#desktop/pages/ticket/composables/useTicketInformation.ts'
import { TICKET_SIDEBAR_SYMBOL } from '#desktop/pages/ticket/composables/useTicketSidebar.ts'
import {
  mockTicketAiAssistanceSummarizeMutation,
  waitForTicketAiAssistanceSummarizeMutationCalls,
} from '#desktop/pages/ticket/graphql/mutations/ticketAIAssistanceSummarize.mocks.ts'

const defaultTicket = createDummyTicket()
const testArticle = createDummyArticle({
  bodyWithUrls: 'foobar',
})

mockRouterHooks()

const onActivatedMock = vi.hoisted(() => (callback?: () => void) => {
  const scope = effectScope()
  scope.run(() => {
    callback?.()
  })
})

vi.mock('vue', async () => {
  const mod = await vi.importActual<typeof import('vue')>('vue')

  return {
    ...mod,
    onActivated: onActivatedMock,
  }
})

const renderRenderTicketSidebarSummary = (
  ticket: Partial<TicketById> = defaultTicket,
) => {
  const wrapper = renderComponent(TicketSidebarSummary, {
    props: {
      sidebar: 'ticket-summary',
      sidebarPlugin: plugin,
      selected: true,
      context: {},
    },
    provide: [
      [
        TICKET_KEY,
        {
          ticket: ref(ticket),
          ticketId: ref(ticket.id),
          ticketInternalId: ref(ticket.internalId),
        },
      ],
      [
        ARTICLES_INFORMATION_KEY,
        {
          articles: computed(() => ({
            totalCount: 1,
            edges: [{ node: testArticle }],
            firstArticles: {
              edges: [{ node: testArticle }],
            },
          })),
          articlesQuery: { watchOnResult: vi.fn() },
        },
      ],
      [
        TICKET_SIDEBAR_SYMBOL,
        {
          switchSidebar: vi.fn(),
          shownSidebars: ref({ 'ticket-summary': true }),
          activeSidebar: ref('ticket-summary'),
          sidebarPlugins: pluginFiles,
          hasSidebar: vi.fn(),
          showSidebar: vi.fn(),
          hideSidebar: vi.fn(),
        },
      ],
    ],
    global: {
      stubs: {
        teleport: true,
      },
    },
    router: true,
    store: true,
  })

  // call  manually onActivated without wrapping component in keep-alive
  onActivatedMock()

  return wrapper
}
const ticketAIAssistanceSummarizeMock = {
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
}

describe('TicketSidebarSummary', () => {
  it('displays correctly,', async () => {
    mockApplicationConfig({
      ai_provider: 'zammad_ai',
      ai_assistance_ticket_summary: true,
      ai_assistance_ticket_summary_config: {
        open_questions: true,
        suggestions: true,
      },
    })

    mockTicketAiAssistanceSummarizeMutation({
      ticketAIAssistanceSummarize: ticketAIAssistanceSummarizeMock,
    })

    const wrapper = renderRenderTicketSidebarSummary()

    expect(wrapper.getAllByIconName(plugin.icon).length).toBe(2)

    expect(
      wrapper.getByRole('button', { name: plugin.title }),
    ).toBeInTheDocument()

    expect(
      await wrapper.findByRole('heading', {
        name: 'Customer Intent',
        level: 3,
      }),
    ).toBeInTheDocument()

    const headings = [
      'Conversation Summary',
      'Customer Intent',
      'Open Questions',
      'Suggested Next Steps',
    ]

    headings.forEach((heading) => {
      expect(
        wrapper.getByRole('heading', {
          name: heading,
          level: 3,
        }),
      ).toBeInTheDocument()
    })

    const content = [
      ticketAIAssistanceSummarizeMock.summary.conversationSummary,
      ...ticketAIAssistanceSummarizeMock.summary.openQuestions,
      ticketAIAssistanceSummarizeMock.summary.problem,
      ...ticketAIAssistanceSummarizeMock.summary.suggestions,
    ]

    content.forEach((text) => {
      expect(wrapper.getByText(text)).toBeInTheDocument()
    })
  })

  it('does not display headings which are disabled,', async () => {
    mockApplicationConfig({
      ai_provider: 'zammad_ai',
      ai_assistance_ticket_summary: true,
      ai_assistance_ticket_summary_config: {
        open_questions: false,
        suggestions: true,
      },
    })

    mockTicketAiAssistanceSummarizeMutation({
      ticketAIAssistanceSummarize: ticketAIAssistanceSummarizeMock,
    })

    const wrapper = renderRenderTicketSidebarSummary()

    expect(wrapper.getAllByIconName(plugin.icon).length).toBe(2)

    expect(
      wrapper.getByRole('button', { name: plugin.title }),
    ).toBeInTheDocument()

    expect(
      await wrapper.findByRole('heading', {
        name: 'Customer Intent',
        level: 3,
      }),
    ).toBeInTheDocument()

    const enabledHeadings = ['Customer Intent', 'Suggested Next Steps']

    const disabledHeadings = ['Open Questions']

    enabledHeadings.forEach((heading) => {
      expect(
        wrapper.getByRole('heading', {
          name: heading,
          level: 3,
        }),
      ).toBeInTheDocument()
    })

    disabledHeadings.forEach((heading) => {
      expect(
        wrapper.queryByRole('heading', {
          name: heading,
          level: 3,
        }),
      ).not.toBeInTheDocument()
    })
  })

  it('hides sidebar when ticket got merged', async () => {
    const wrapper = renderRenderTicketSidebarSummary({
      state: {
        name: 'merged',
        id: convertToGraphQLId('State', 5),
        stateType: {
          id: convertToGraphQLId('StateType', 6),
          name: 'merged',
        },
      },
    })

    await waitFor(() => expect(wrapper.emitted('hide')).toBeTruthy())
  })

  it('displays content hint', async () => {
    mockTicketAiAssistanceSummarizeMutation({
      ticketAIAssistanceSummarize: ticketAIAssistanceSummarizeMock,
    })

    mockApplicationConfig({
      ai_provider: 'zammad_ai',
      ai_assistance_ticket_summary: true,
      ai_assistance_ticket_summary_config: {
        open_questions: true,
        suggestions: true,
      },
    })

    const wrapper = renderRenderTicketSidebarSummary()

    expect(
      await wrapper.findByText(
        'Be sure to check AI-generated summaries for accuracy.',
      ),
    ).toBeInTheDocument()
  })

  it('shows info that summary is too short to be generated', async () => {
    mockTicketAiAssistanceSummarizeMutation({
      ticketAIAssistanceSummarize: {
        summary: {
          problem: null,
          conversationSummary: null,
          openQuestions: null,
          suggestions: null,
        },
      },
    })

    mockApplicationConfig({
      ai_provider: 'zammad_ai',
      ai_assistance_ticket_summary: true,
      ai_assistance_ticket_summary_config: {
        open_questions: true,
        suggestions: true,
      },
    })

    const wrapper = renderRenderTicketSidebarSummary()

    expect(
      await wrapper.findByText(
        'There is not enough content yet to summarize this ticket.',
      ),
    ).toBeInTheDocument()
  })

  it('shows skeleton loader when summary is not ready', async () => {
    mockTicketAiAssistanceSummarizeMutation({
      ticketAIAssistanceSummarize: {
        summary: null,
      },
    })

    const wrapper = renderRenderTicketSidebarSummary()

    expect(
      wrapper.getByText(
        'Zammad Smart Assist is generating the summary for you…',
      ),
    ).toBeInTheDocument()
    expect(
      wrapper.getAllByLabelText('Placeholder for AI generated heading'),
    ).toHaveLength(4)

    expect(
      wrapper.getAllByLabelText('Placeholder for AI generated text'),
    ).toHaveLength(16)
  })

  it('hides feature if feature flag is disabled', async () => {
    mockApplicationConfig({
      checklist: false,
    })

    mockApplicationConfig({
      ai_provider: 'zammad_ai',
      ai_assistance_ticket_summary: true,
      ai_assistance_ticket_summary_config: {
        open_questions: true,
        suggestions: true,
      },
    })

    mockTicketAiAssistanceSummarizeMutation({
      ticketAIAssistanceSummarize: ticketAIAssistanceSummarizeMock,
    })

    const wrapper = renderRenderTicketSidebarSummary()

    await waitForTicketAiAssistanceSummarizeMutationCalls()

    expect(
      wrapper.queryByRole('button', { name: 'Add all to checklist' }),
    ).not.toBeInTheDocument()

    expect(
      wrapper.queryAllByRole('button', { name: 'Add as checklist item' })
        .length,
    ).toBe(0)
  })
})
