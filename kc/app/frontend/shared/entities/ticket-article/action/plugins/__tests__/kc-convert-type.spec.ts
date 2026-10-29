// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { setupView } from '#tests/support/mock-user.ts'

import { createTicketArticle, createTestArticleActions, createTicket } from './utils.ts'

const hasSendAsEmail = (actions: { name: string }[]) =>
  actions.some((action) => action.name === 'kc-convert-to-email')

describe('KC "Send as email reply" action', () => {
  beforeEach(() => {
    setupView('agent')
  })

  it('is offered on an internal note', () => {
    const ticket = createTicket()
    const article = createTicketArticle({
      internal: true,
      type: { name: 'note' },
    })

    expect(hasSendAsEmail(createTestArticleActions(ticket, article, 'desktop'))).toBe(true)
  })

  it('is not offered on a public note', () => {
    const ticket = createTicket()
    const article = createTicketArticle({
      internal: false,
      type: { name: 'note' },
    })

    expect(hasSendAsEmail(createTestArticleActions(ticket, article, 'desktop'))).toBe(false)
  })

  it('offers no conversion on an email', () => {
    const ticket = createTicket()
    const article = createTicketArticle({ type: { name: 'email' } })
    const actions = createTestArticleActions(ticket, article, 'desktop')

    expect(actions.some((action) => action.name.startsWith('kc-convert-to'))).toBe(false)
  })

  it('is not offered when the group has no email address', () => {
    const ticket = createTicket({ group: { emailAddress: null } })
    const article = createTicketArticle({
      internal: true,
      type: { name: 'note' },
    })

    expect(hasSendAsEmail(createTestArticleActions(ticket, article, 'desktop'))).toBe(false)
  })
})
