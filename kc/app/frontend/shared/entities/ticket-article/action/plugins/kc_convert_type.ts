// KC: "Send as email reply" on an existing internal note in the Vue 3
// frontends.
//
// Opens a new email reply to the customer with the note's text, so an
// internal draft written as a note can be sent to the customer without
// copying it by hand. The reverse direction (email -> note) is not offered:
// switching the type of the reply being written already keeps its text in
// the reply form, which is what the legacy note/email toggle
// (kc_convert_type.coffee) does there.
//
// Only offered when the ticket's group has an email address.

import type {
  TicketArticleAction,
  TicketArticleActionPlugin,
} from './types.ts'

const actionPlugin: TicketArticleActionPlugin = {
  // Priority 150 — between Note (100) and Email (200), same as legacy.
  order: 150,

  addActions(ticket, article) {
    if (article.type?.name !== 'note' || !article.internal) return []
    if (!ticket.group.emailAddress) return []

    const action: TicketArticleAction = {
      apps: ['mobile', 'desktop'],
      label: __('Send as email reply'),
      name: 'kc-convert-to-email',
      icon: 'mail',
      view: {
        agent: ['change'],
      },
      perform(ticket, article, { openReplyForm }) {
        const values: Record<string, unknown> = {
          articleType: 'email',
          body: article.bodyWithUrls || '',
          subtype: 'reply',
        }

        if (ticket.customer?.email) {
          values.to = [ticket.customer.email]
        }

        openReplyForm(values)
      },
    }
    return [action]
  },
}

export default actionPlugin
