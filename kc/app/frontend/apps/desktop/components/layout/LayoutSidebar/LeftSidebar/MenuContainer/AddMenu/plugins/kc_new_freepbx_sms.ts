// KC: AddMenu plugin that adds "New SMS Message (FreePBX)" to the left
// sidebar add menu in the Vue 3 desktop-view.
//
// Mirrors the legacy NavBarRight registration from
// kc_new_freepbx_sms_conversation.coffee. Shown only while FreePBX text
// messaging is switched on (kc_freepbx_sms_enabled), read from the
// application config the same way the legacy nav bar reads the setting.

import { useApplicationStore } from '#shared/stores/application.ts'

import type { AddMenuItem } from '#desktop/components/layout/LayoutSidebar/LeftSidebar/types.ts'

export default {
  key: 'kc-new-freepbx-sms',
  permission: ['ticket.agent'],
  order: 201,
  label: __('New SMS Message (FreePBX)'),
  variant: 'secondary',
  icon: 'sms',
  link: '/kc/new_freepbx_sms',
  show() {
    const { config } = useApplicationStore()

    return config.kc_freepbx_sms_enabled === true
  },
} as AddMenuItem
