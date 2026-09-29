// KC: Article action plugin for FreePBX SMS reply in the Vue 3 desktop-view.
//
// Mirrors kc_ringcentral_sms.ts for tickets whose texts go through the
// FreePBX connector. Adds "freepbx_sms_message" as:
//   - A reply action on all FreePBX SMS articles (both directions)
//   - An available article type in the compose area for FreePBX SMS tickets
//
// A FreePBX SMS ticket is identified by either:
//   1. ticket.createArticleType.name === 'freepbx_sms_message'
//   2. ticket.preferences.freepbx_sms exists (skip-send and missed-call tickets)

import type {
  TicketArticleAction,
  TicketArticleActionPlugin,
  TicketArticleType,
} from './types.ts'

interface FreepbxSmsPreferences {
  from_phone?: string
  to_phone?: string
  channel_id?: number
  conversation_key?: string
}

const isSmsTicket = (ticket: {
  createArticleType?: { name?: string } | null
  preferences?: Record<string, unknown> | null
}): boolean => {
  if (ticket.createArticleType?.name === 'freepbx_sms_message') return true
  if (ticket.preferences?.freepbx_sms) return true
  return false
}

const getSmsPreferences = (ticket: {
  preferences?: Record<string, unknown> | null
}): FreepbxSmsPreferences | null => {
  const prefs = ticket.preferences?.freepbx_sms as
    | FreepbxSmsPreferences
    | undefined
  return prefs ?? null
}

const actionPlugin: TicketArticleActionPlugin = {
  order: 311,

  addActions(ticket, article) {
    if (article.type?.name !== 'freepbx_sms_message') return []

    const action: TicketArticleAction = {
      apps: ['mobile', 'desktop'],
      label: __('Reply'),
      name: 'freepbx_sms_message',
      icon: 'reply',
      view: {
        agent: ['change'],
      },
      perform(ticket, article, { openReplyForm }) {
        const from = article.from?.raw
        const smsPrefs = getSmsPreferences(ticket)
        const articleData = {
          articleType: 'freepbx_sms_message',
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
      value: 'freepbx_sms_message',
      label: __('FreePBX SMS'),
      buttonLabel: __('FreePBX SMS'),
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
