// KC: AddMenu plugin that adds a "New Teams Chat" item to the left
// sidebar add menu in the Vue 3 desktop-view.
//
// Mirrors the legacy NavBarRight registration from
// kc_new_teams_conversation.coffee for the modern frontend.

import type { AddMenuItem } from '#desktop/components/layout/LayoutSidebar/LeftSidebar/types.ts'

export default {
  key: 'kc-new-teams',
  permission: ['ticket.agent'],
  order: 300,
  label: __('New Teams Chat'),
  variant: 'secondary',
  icon: 'chat',
  link: '/kc/new-teams',
} as AddMenuItem
