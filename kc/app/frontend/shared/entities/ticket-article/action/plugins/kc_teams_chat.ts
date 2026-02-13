// KC: Article action plugin for Microsoft Teams Chat reply in the Vue 3
// desktop-view.
//
// Mirrors the logic of the legacy CoffeeScript plugin
// (kc_teams_chat_reply.coffee) for the modern frontend.
//
// Adds "teams_chat_message" as:
//   - A reply action on inbound Teams Chat articles
//   - An available article type in the compose area for Teams Chat tickets
//
// A Teams Chat ticket is identified by:
//   ticket.createArticleType.name === 'teams_chat_message'

import type {
  TicketArticleAction,
  TicketArticleActionPlugin,
  TicketArticleType,
} from './types.ts'

const isTeamsChatTicket = (ticket: {
  createArticleType?: { name?: string } | null
}): boolean => {
  return ticket.createArticleType?.name === 'teams_chat_message'
}

const actionPlugin: TicketArticleActionPlugin = {
  order: 320,

  // Show reply action on any teams_chat_message article regardless of sender.
  // Matches legacy kc_teams_chat_reply.coffee which only checks article type,
  // allowing agent-to-agent threading in Teams conversations.
  addActions(ticket, article) {
    if (article.type?.name !== 'teams_chat_message') return []

    const action: TicketArticleAction = {
      apps: ['mobile', 'desktop'],
      label: __('Reply'),
      name: 'teams-chat-reply',
      icon: 'reply',
      view: {
        agent: ['change'],
      },
      perform(ticket, article, { openReplyForm }) {
        openReplyForm({
          articleType: 'teams_chat_message',
          inReplyTo: article.messageId,
        })
      },
    }
    return [action]
  },

  addTypes(ticket) {
    if (!isTeamsChatTicket(ticket)) return []

    const type: TicketArticleType = {
      apps: ['mobile', 'desktop'],
      value: 'teams_chat_message',
      label: __('Teams Chat'),
      buttonLabel: __('Add message'),
      icon: 'chat',
      view: {
        agent: ['change'],
      },
      internal: false,
      contentType: 'text/plain',
      fields: {
        body: {
          required: true,
        },
        attachments: {},
      },
    }
    return [type]
  },
}

export default actionPlugin
