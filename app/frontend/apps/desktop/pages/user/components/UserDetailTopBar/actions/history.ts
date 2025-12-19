// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import type { UserInfoActionPlugin } from './types.ts'

export default <UserInfoActionPlugin>{
  key: 'history-user',
  label: __('History'),
  icon: 'clock-history',
  order: 300,
  permission: 'ticket.agent',
  onClick: () => {
    // :TODO
  },
}
