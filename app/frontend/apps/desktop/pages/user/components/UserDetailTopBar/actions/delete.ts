// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import type { UserInfoActionPlugin } from './types.ts'

export default <UserInfoActionPlugin>{
  key: 'delete-user',
  label: __('Delete'),
  icon: 'trash',
  order: 400,
  permission: ['admin.data_privacy', 'admin.user'],
  onClick: () => {
    // :TODO
  },
}
