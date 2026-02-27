// KC: Sidebar plugin for per-agent time tracking.
// Displays time entries grouped by agent with add/delete capabilities.
// Auto-discovered by Vite's import.meta.glob in plugins/index.ts.

import { TicketSidebarScreenType } from '#desktop/pages/ticket/types/sidebar.ts'

import TicketSidebarKcTimeTracking from '../TicketSidebarKcTimeTracking/TicketSidebarKcTimeTracking.vue'

import type { TicketSidebarPlugin } from './types.ts'

export default <TicketSidebarPlugin>{
  title: __('Time Tracking'),
  component: TicketSidebarKcTimeTracking,
  permissions: ['ticket.agent'],
  screens: [TicketSidebarScreenType.TicketDetailView],
  views: ['agent'],
  icon: 'clock',
  order: 7500,
}
