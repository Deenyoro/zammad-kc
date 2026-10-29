// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// KC: BCC on email replies in the new desktop UI. BCC is revealed via an "Add BCC" link on the CC
//  row (mirroring upstream's "Add CC") and its value must reach the ticketUpdate mutation as
//  article.bcc.

import { getNode } from '@formkit/core'
import { within } from '@testing-library/vue'

import { visitView } from '#tests/support/components/visitView.ts'
import { mockApplicationConfig } from '#tests/support/mock-applicationConfig.ts'
import { mockPermissions } from '#tests/support/mock-permissions.ts'

import {
  mockAutocompleteSearchRecipientQuery,
  waitForAutocompleteSearchRecipientQueryCalls,
} from '#shared/components/Form/fields/FieldRecipient/graphql/queries/autocompleteSearch/recipient.mocks.ts'
import { mockFormUpdaterQuery } from '#shared/components/Form/graphql/queries/formUpdater.mocks.ts'
import { waitForTicketUpdateMutationCalls } from '#shared/entities/ticket/graphql/mutations/update.mocks.ts'
import { mockTicketArticlesQuery } from '#shared/entities/ticket/graphql/queries/ticket/articles.mocks.ts'
import { mockTicketQuery } from '#shared/entities/ticket/graphql/queries/ticket.mocks.ts'
import { createDummyArticle } from '#shared/entities/ticket-article/__tests__/mocks/ticket-articles.ts'
import { createDummyTicket } from '#shared/entities/ticket-article/__tests__/mocks/ticket.ts'
import { convertToGraphQLId } from '#shared/graphql/utils.ts'

import { mockLinkListQuery } from '#desktop/entities/link/graphql/queries/linkList.mocks.ts'

const openEmailReply = async () => {
  mockTicketQuery({
    ticket: createDummyTicket({
      group: {
        id: convertToGraphQLId('Group', 1),
        emailAddress: {
          name: 'Zammad Helpdesk',
          emailAddress: 'zammad@localhost',
        },
      },
      articleType: 'email',
      defaultPolicy: {
        update: true,
        agentReadAccess: true,
      },
    }),
  })

  mockTicketArticlesQuery({
    articles: {
      totalCount: 1,
      edges: [
        {
          node: createDummyArticle({
            articleType: 'email',
            internal: false,
          }),
        },
      ],
    },
  })

  mockFormUpdaterQuery({
    formUpdater: {
      fields: {
        group_id: { options: [{ value: 1, label: 'Users' }] },
        owner_id: { options: [{ value: 3, label: 'Test Admin Agent' }] },
        state_id: {
          options: [
            { value: 4, label: 'closed' },
            { value: 2, label: 'open' },
          ],
        },
        pending_time: { show: false },
        priority_id: { options: [{ value: 2, label: '2 normal' }] },
      },
      flags: {
        newArticlePresent: false,
      },
    },
  })

  const view = await visitView('/tickets/1')

  const articles = await view.findAllByRole('article')

  await view.events.click(await within(articles[0]).findByRole('button', { name: 'Reply' }))

  expect(await view.findByLabelText('To')).toBeInTheDocument()

  return view
}

describe('Ticket detail view - KC BCC', () => {
  beforeEach(() => {
    mockPermissions(['ticket.agent'])

    mockLinkListQuery({
      linkList: [],
    })
  })

  it('reveals BCC via "Add BCC" and sends it as article.bcc', async () => {
    const view = await openEmailReply()

    await view.events.type(await view.findByRole('textbox', { name: 'Text' }), 'Foo email')

    // BCC is hidden like CC, and its link only shows once CC is revealed.
    expect(view.getByLabelText('BCC').closest('.formkit-outer')).toHaveClass('hidden')
    expect(view.queryByRole('link', { name: 'Add BCC' })).not.toBeInTheDocument()

    await view.events.click(view.getByRole('link', { name: 'Add CC' }))
    await view.events.click(view.getByRole('link', { name: 'Add BCC' }))

    const bcc = view.getByLabelText('BCC')
    expect(bcc.closest('.formkit-outer')).not.toHaveClass('hidden')
    expect(bcc).toHaveFocus()
    expect(view.queryByRole('link', { name: 'Add BCC' })).not.toBeInTheDocument()

    mockAutocompleteSearchRecipientQuery({
      autocompleteSearchRecipient: [],
    })

    await view.events.type(within(bcc).getByRole('searchbox'), 'hidden@example.com')
    await waitForAutocompleteSearchRecipientQueryCalls()
    await view.events.click(view.getByRole('button', { name: 'add new email address' }))

    await getNode('form-ticket-edit-1')?.settled

    await view.events.click(view.getByRole('button', { name: 'Update' }))

    const calls = await waitForTicketUpdateMutationCalls()

    expect(calls?.at(-1)?.variables).toEqual(
      expect.objectContaining({
        input: expect.objectContaining({
          article: expect.objectContaining({
            body: 'Foo email',
            bcc: ['hidden@example.com'],
          }),
        }),
      }),
    )
    // Not leaked into the ticket attributes.
    expect(calls?.at(-1)?.variables.input).not.toHaveProperty('bcc')
    // Full reply flow incl. recipient autocomplete is slower than the 5s default.
  }, 20_000)

  it('does not offer BCC when the kc_bcc_access setting disables it', async () => {
    mockApplicationConfig({
      kc_bcc_access: 'disabled',
    })

    const view = await openEmailReply()

    await view.events.click(view.getByRole('link', { name: 'Add CC' }))

    expect(view.queryByRole('link', { name: 'Add BCC' })).not.toBeInTheDocument()
  })
})
