// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import '#tests/graphql/builders/mocks.ts'

import { createPinia, setActivePinia } from 'pinia'
import { ref } from 'vue'

import { convertToGraphQLId } from '#shared/graphql/utils.ts'

import {
  mockTicketUpdateBulkMutation,
  waitForTicketUpdateBulkMutationCalls,
} from '#desktop/entities/ticket/graphql/mutations/updateBulk.mocks.ts'

import { useDragAndDropBulk } from '../useDragAndDropBulk.ts'

// We try to simulate the table action as in an integration test
const triggerDragAndDrop = async ({
  rowItemId,
  target,
}: {
  rowItemId: string
  target: HTMLElement
}) => {
  const row = document.createElement('tr')
  row.dataset.itemId = rowItemId

  const rowInner = document.createElement('td')
  row.appendChild(rowInner)

  document.body.appendChild(row)
  document.body.appendChild(target)

  rowInner.dispatchEvent(
    new PointerEvent('pointerdown', {
      bubbles: true,
      button: 0,
      clientX: 10,
      clientY: 10,
    }),
  )

  document.dispatchEvent(
    new PointerEvent('pointermove', {
      bubbles: true,
      clientX: 30,
      clientY: 30,
    }),
  )

  await vi.advanceTimersByTimeAsync(250)

  const targetInner = document.createElement('span')
  target.appendChild(targetInner)

  targetInner.dispatchEvent(
    new PointerEvent('pointerup', {
      bubbles: true,
    }),
  )

  row.remove()
  target.remove()
}

describe('useDragAndDropBulk', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
    document.body.innerHTML = ''
  })

  it('calls ticket bulk update mutation when dropping on a macro target', async () => {
    const ticketId = convertToGraphQLId('Ticket', 1)
    const macroId = convertToGraphQLId('Macro', 1)

    mockTicketUpdateBulkMutation({
      ticketUpdateBulk: {
        async: false,
        total: 1,
        failedCount: 0,
        invalidTicketIds: [],
        inaccessibleTicketIds: [],
      },
    })

    useDragAndDropBulk({
      checkedTicketIds: ref(new Set([ticketId])),
      bulkContext: ref(undefined),
      bulkCount: ref(undefined),
    })

    const macroTarget = document.createElement('li')
    macroTarget.id = macroId
    macroTarget.dataset.type = 'macro'

    await triggerDragAndDrop({ rowItemId: ticketId, target: macroTarget })

    const calls = await waitForTicketUpdateBulkMutationCalls()

    expect(calls.at(-1)?.variables).toEqual({
      selector: {
        entityIds: [ticketId],
      },
      perform: {
        macroId,
      },
    })
  })

  it('uses overview id selector when bulk count and overview context are present', async () => {
    const ticketId = convertToGraphQLId('Ticket', 1)
    const macroId = convertToGraphQLId('Macro', 2)
    const overviewId = convertToGraphQLId('Overview', 1)

    mockTicketUpdateBulkMutation({
      ticketUpdateBulk: {
        async: false,
        total: 1,
        failedCount: 0,
        invalidTicketIds: [],
        inaccessibleTicketIds: [],
      },
    })

    useDragAndDropBulk({
      checkedTicketIds: ref(new Set([ticketId])),
      bulkContext: ref({ overviewId }),
      bulkCount: ref(10),
    })

    const macroTarget = document.createElement('li')
    macroTarget.id = macroId
    macroTarget.dataset.type = 'macro'

    await triggerDragAndDrop({ rowItemId: ticketId, target: macroTarget })

    const calls = await waitForTicketUpdateBulkMutationCalls()

    expect(calls.at(-1)?.variables).toEqual({
      selector: {
        overviewId,
      },
      perform: {
        macroId,
      },
    })
  })

  it('uses search query selector when bulk count and search context are present', async () => {
    const ticketId = convertToGraphQLId('Ticket', 1)
    const macroId = convertToGraphQLId('Macro', 3)

    mockTicketUpdateBulkMutation({
      ticketUpdateBulk: {
        async: false,
        total: 1,
        failedCount: 0,
        invalidTicketIds: [],
        inaccessibleTicketIds: [],
      },
    })

    useDragAndDropBulk({
      checkedTicketIds: ref(new Set([ticketId])),
      bulkContext: ref({ searchQuery: 'state:new' }),
      bulkCount: ref(10),
    })

    const macroTarget = document.createElement('li')
    macroTarget.id = macroId
    macroTarget.dataset.type = 'macro'

    await triggerDragAndDrop({ rowItemId: ticketId, target: macroTarget })

    const calls = await waitForTicketUpdateBulkMutationCalls()

    expect(calls.at(-1)?.variables).toEqual({
      selector: {
        searchQuery: 'state:new',
      },
      perform: {
        macroId,
      },
    })
  })
})
