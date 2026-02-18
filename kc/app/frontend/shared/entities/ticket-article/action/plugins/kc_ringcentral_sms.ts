// KC: Article action plugin for RingCentral SMS reply in the Vue 3 desktop-view.
//
// Mirrors the logic of the legacy CoffeeScript plugin
// (kc_ringcentral_sms_reply.coffee) for the modern frontend.
//
// Adds "ringcentral_sms_message" as:
//   - A reply action on inbound RingCentral SMS articles
//   - An available article type in the compose area for SMS tickets
//   - The primary (default) reply channel for SMS tickets
//
// An SMS ticket is identified by either:
//   1. ticket.createArticleType.name === 'ringcentral_sms_message'
//   2. ticket.preferences.ringcentral_sms exists (fallback for older tickets)
//
// The customer's phone number is read from ticket.preferences.ringcentral_sms.from_phone
// and pre-filled as the recipient when composing a reply. The backend delivery job
// (Kc::CommunicateRingcentralSmsJob) also falls back to this preference when
// article-level preferences are absent.

import { EnumTicketArticleSenderName } from '#shared/graphql/types.ts'

import type {
  TicketArticleAction,
  TicketArticleActionPlugin,
  TicketArticleType,
} from './types.ts'

interface RingcentralSmsPreferences {
  from_phone?: string
  to_phone?: string
  channel_id?: number
  conversation_key?: string
}

const isSmsTicket = (ticket: {
  createArticleType?: { name?: string } | null
  preferences?: Record<string, unknown> | null
}): boolean => {
  if (ticket.createArticleType?.name === 'ringcentral_sms_message') return true
  if (ticket.preferences?.ringcentral_sms) return true
  return false
}

const getSmsPreferences = (ticket: {
  preferences?: Record<string, unknown> | null
}): RingcentralSmsPreferences | null => {
  const prefs = ticket.preferences?.ringcentral_sms as
    | RingcentralSmsPreferences
    | undefined
  return prefs ?? null
}

const actionPlugin: TicketArticleActionPlugin = {
  order: 310,

  addActions(ticket, article) {
    if (
      article.sender?.name !== EnumTicketArticleSenderName.Customer ||
      article.type?.name !== 'ringcentral_sms_message'
    )
      return []

    const action: TicketArticleAction = {
      apps: ['mobile', 'desktop'],
      label: __('Reply'),
      name: 'ringcentral_sms_message',
      icon: 'reply',
      view: {
        agent: ['change'],
      },
      perform(ticket, article, { openReplyForm }) {
        const from = article.from?.raw
        const smsPrefs = getSmsPreferences(ticket)
        const articleData = {
          articleType: 'ringcentral_sms_message',
          to: from ? [from] : smsPrefs?.from_phone ? [smsPrefs.from_phone] : [],
          inReplyTo: article.messageId,
        }

        openReplyForm(articleData)
      },
    }
    return [action]
  },

  addTypes(ticket) {
    if (!isSmsTicket(ticket)) return []

    const type: TicketArticleType = {
      apps: ['mobile', 'desktop'],
      value: 'ringcentral_sms_message',
      label: __('RingCentral SMS'),
      buttonLabel: __('RingCentral SMS'),
      icon: 'message',
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
      performReply(ticket) {
        const smsPrefs = getSmsPreferences(ticket)
        return {
          to: smsPrefs?.from_phone ? [smsPrefs.from_phone] : [],
        }
      },
    }
    return [type]
  },
}

export default actionPlugin
