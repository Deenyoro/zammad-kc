// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import type { UserInfoActionPlugin } from './types.ts'

export default <UserInfoActionPlugin>{
  key: 'new-ticket',
  label: __('New Ticket'),
  icon: 'plus-square-fill',
  variant: 'secondary',
  showLabel: true,
  permission: 'ticket.agent',
  order: 200,
  topLevel: true,
  onClick: () => {
    // :TODO
  },
}
