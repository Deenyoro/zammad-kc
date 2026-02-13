// KC: Sidebar plugin for scheduled replies.
// Allows agents to schedule article replies for future delivery and
// view/cancel pending scheduled articles.
// Auto-discovered by Vite's import.meta.glob in plugins/index.ts.

import { TicketSidebarScreenType } from '#desktop/pages/ticket/types/sidebar.ts'

import TicketSidebarKcScheduledReplies from '../TicketSidebarKcScheduledReplies/TicketSidebarKcScheduledReplies.vue'

import type { TicketSidebarPlugin } from './types.ts'

export default <TicketSidebarPlugin>{
  title: __('Scheduled Replies'),
  component: TicketSidebarKcScheduledReplies,
  permissions: ['ticket.agent'],
  screens: [TicketSidebarScreenType.TicketDetailView],
  icon: 'calendar-event',
  order: 7600,
}
