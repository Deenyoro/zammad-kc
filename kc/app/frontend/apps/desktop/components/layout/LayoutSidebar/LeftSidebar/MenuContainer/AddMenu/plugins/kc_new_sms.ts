// KC: AddMenu plugin that adds a "New SMS" item to the left sidebar
// add menu in the Vue 3 desktop-view.
//
// Mirrors the legacy NavBarRight registration from
// kc_new_sms_conversation.coffee for the modern frontend.

import type { AddMenuItem } from '#desktop/components/layout/LayoutSidebar/LeftSidebar/types.ts'

export default {
  key: 'kc-new-rcsms',
  permission: ['ticket.agent'],
  order: 200,
  label: __('New SMS Message (RingCentral)'),
  variant: 'secondary',
  icon: 'sms',
  link: '/kc/new_rcsms',
} as AddMenuItem
