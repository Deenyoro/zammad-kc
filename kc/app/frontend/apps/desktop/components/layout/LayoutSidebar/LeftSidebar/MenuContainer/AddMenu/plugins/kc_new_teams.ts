// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// KC: AddMenu plugin that adds a "New Teams Message" item to the left
// sidebar add menu in the Vue 3 desktop-view.
//
// Mirrors the legacy NavBarRight registration from
// kc_new_teams_conversation.coffee for the modern frontend.

import type { AddMenuItem } from '#desktop/components/layout/LayoutSidebar/LeftSidebar/types.ts'

export default {
  key: 'kc-new-teams',
  permission: ['ticket.agent'],
  order: 300,
  label: __('New Teams Message'),
  variant: 'secondary',
  icon: 'chat',
  link: '/kc/new_teams',
} as AddMenuItem
