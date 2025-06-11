// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/
import { ref } from 'vue'

import { renderComponent } from '#tests/support/components/index.ts'

import { createDummyTicket } from '#shared/entities/ticket-article/__tests__/mocks/ticket.ts'
import { convertToGraphQLId } from '#shared/graphql/utils.ts'

import TicketSummaryCreateChecklist from '#desktop/pages/ticket/components/TicketSidebar/TicketSidebarSummary/TicketSidebarSummaryContent/TicketSummaryCreateChecklist.vue'
import { TICKET_KEY } from '#desktop/pages/ticket/composables/useTicketInformation.ts'
import { TICKET_SIDEBAR_SYMBOL } from '#desktop/pages/ticket/composables/useTicketSidebar.ts'
import {
  mockTicketChecklistAddMutation,
  waitForTicketChecklistAddMutationCalls,
} from '#desktop/pages/ticket/graphql/mutations/ticketChecklistAdd.mocks.ts'
import { waitForTicketChecklistItemsAddMutationCalls } from '#desktop/pages/ticket/graphql/mutations/ticketChecklistItemsAdd.mocks.ts'
import { waitForTicketChecklistItemUpsertMutationCalls } from '#desktop/pages/ticket/graphql/mutations/ticketChecklistItemUpsert.mocks.ts'

const ticket = createDummyTicket({ checklist: null })

const switchSidebar = vi.fn()

const summary = ['Test checklist item A', 'Test checklist item B']

const renderTicketSummaryCreateChecklist = (summaryArg = summary, ticketArg = ticket) =>
  renderComponent(TicketSummaryCreateChecklist, {
    props: {
      summary: summaryArg,
      label: 'Checklist heading',
    },
    provide: [
      [
        TICKET_KEY,
        {
          ticket: ref(ticketArg),
          ticketId: ref(ticketArg.id),
          ticketInternalId: ref(ticketArg.internalId),
        },
      ],
      [
        TICKET_SIDEBAR_SYMBOL,
        {
          switchSidebar,
        },
      ],
    ],
  })

describe('TicketSummaryCreateChecklist', () => {
  it('render correctly', () => {
    const wrapper = renderTicketSummaryCreateChecklist()

    expect(wrapper.getByRole('heading', { level: 3 })).toHaveTextContent('Checklist heading')

    expect(wrapper.getAllByRole('button', { name: 'Add as checklist item' }).length).toBe(2)
  })

  it('converts summary item to checklist item if checklist is NOT available', async () => {
    const wrapper = renderTicketSummaryCreateChecklist()

    const buttons = wrapper.getAllByRole('button', {
      name: 'Add as checklist item',
    })

    await wrapper.events.click(buttons[0])

    const mockedChecklistId = convertToGraphQLId('Checklist', 3)

    const mockedChecklistItem = {
      id: convertToGraphQLId('Checklist::Item', 1),
      text: '',
    }

    mockTicketChecklistAddMutation({
      ticketChecklistAdd: {
        checklist: {
          name: '',
          id: mockedChecklistId,
          items: [mockedChecklistItem],
        },
      },
    })

    const calls = await waitForTicketChecklistAddMutationCalls()

    expect(calls.at(-1)?.variables).toEqual({
      ticketId: ticket.id,
    })

    const upsertCalls = await waitForTicketChecklistItemUpsertMutationCalls()

    expect(upsertCalls.at(-1)?.variables).toEqual({
      checklistId: expect.any(String), // mocker does not return mockedChecklistId
      input: {
        text: summary[0],
        checked: false,
      },
    })
  })

  it('converts summary item to checklist item if checklist is available', async () => {
    const checklistId = convertToGraphQLId('Checklist', 23)
    const wrapper = renderTicketSummaryCreateChecklist(summary, {
      ...ticket,
      checklist: {
        id: checklistId,
        incomplete: 3,
        completed: false,
        complete: 0,
        total: 3,
      },
    })

    const buttons = wrapper.getAllByRole('button', {
      name: 'Add as checklist item',
    })

    await wrapper.events.click(buttons[0])

    const calls = await waitForTicketChecklistItemUpsertMutationCalls()

    expect(calls.at(-1)?.variables).toEqual({
      checklistId,
      input: {
        text: summary[0],
        checked: false,
      },
    })

    // :TODO if we plan to initialize CommonNotifications as an option with renderComponent
    // expect(
    //   await wrapper.findByRole('alert', {
    //     name: 'Checklist item successfully added.',
    //   }),
    // ).toBeInTheDocument()
  })

  it('converts all summaries to checklist items if list is NOT available', async () => {
    const wrapper = renderTicketSummaryCreateChecklist()

    await wrapper.events.click(wrapper.getByRole('button', { name: 'Add all to checklist' }))

    const mockedChecklistId = convertToGraphQLId('Checklist', 3)

    const mockedChecklistItem = {
      id: convertToGraphQLId('Checklist::Item', 1),
      text: '',
    }

    mockTicketChecklistAddMutation({
      ticketChecklistAdd: {
        checklist: {
          name: '',
          id: mockedChecklistId,
          items: [mockedChecklistItem],
        },
      },
    })

    const calls = await waitForTicketChecklistAddMutationCalls()

    expect(calls.at(-1)?.variables).toEqual({
      ticketId: ticket.id,
    })

    const itemsAddCalls = await waitForTicketChecklistItemsAddMutationCalls()

    expect(itemsAddCalls.at(-1)?.variables).toEqual({
      checklistId: expect.any(String), // mocker does not return mockedChecklistId
      input: [
        {
          text: summary[0],
          checked: false,
        },
        {
          text: summary[1],
          checked: false,
        },
      ],
    })
  })

  it('converts all summaries to checklist items', async () => {
    const checklistId = convertToGraphQLId('Checklist', 23)

    const wrapper = renderTicketSummaryCreateChecklist(summary, {
      ...ticket,
      checklist: {
        id: checklistId,
        completed: false,
        incomplete: 3,
        complete: 0,
        total: 3,
      },
    })

    await wrapper.events.click(wrapper.getByRole('button', { name: 'Add all to checklist' }))

    const itemsAddCalls = await waitForTicketChecklistItemsAddMutationCalls()

    expect(itemsAddCalls.at(-1)?.variables).toEqual({
      checklistId,
      input: [
        {
          text: summary[0],
          checked: false,
        },
        {
          text: summary[1],
          checked: false,
        },
      ],
    })

    expect(switchSidebar).toHaveBeenCalledWith('checklist')
  })
})
