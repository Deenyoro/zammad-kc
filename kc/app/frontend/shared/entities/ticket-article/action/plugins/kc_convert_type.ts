// KC: Convert between Note and Email Reply article types in the Vue 3
// desktop-view.
//
// Mirrors the logic of the legacy CoffeeScript plugin
// (kc_convert_type.coffee) for the modern frontend, but uses a cleaner
// architecture: instead of DOM-injected buttons and MutationObservers,
// this uses the standard article action plugin system.
//
// Adds two actions:
//   - "Convert to Email Reply" on note articles (when the group has email)
//   - "Convert to Note" on email articles
//
// Body content is preserved during conversion. When converting to email,
// the customer's email address is pre-filled as the recipient.

import type {
  TicketArticleAction,
  TicketArticleActionPlugin,
} from './types.ts'

interface ConversionTarget {
  articleType: string
  icon: string
  label: string
}

const CONVERSIONS: Record<string, ConversionTarget> = {
  note: {
    articleType: 'email',
    icon: 'mail',
    label: __('Convert to Email Reply'),
  },
  email: {
    articleType: 'note',
    icon: 'note',
    label: __('Convert to Note'),
  },
}

const actionPlugin: TicketArticleActionPlugin = {
  // Priority 150 — between Note (100) and Email (200), same as legacy.
  order: 150,

  addActions(ticket, article) {
    const typeName = article.type?.name
    if (!typeName) return []

    const target = CONVERSIONS[typeName]
    if (!target) return []

    // Note → Email: only available when the group has an email address.
    if (typeName === 'note' && !ticket.group.emailAddress) return []

    const action: TicketArticleAction = {
      apps: ['mobile', 'desktop'],
      label: target.label,
      name: `kc-convert-to-${target.articleType}`,
      icon: target.icon,
      view: {
        agent: ['change'],
      },
      perform(ticket, article, { openReplyForm }) {
        const values: Record<string, unknown> = {
          articleType: target.articleType,
          body: article.bodyWithUrls || '',
        }

        if (target.articleType === 'email') {
          if (ticket.customer?.email) {
            values.to = [ticket.customer.email]
          }
          values.subtype = 'reply'
        }

        if (target.articleType === 'note') {
          values.internal = true
        }

        openReplyForm(values)
      },
    }
    return [action]
  },
}

export default actionPlugin
