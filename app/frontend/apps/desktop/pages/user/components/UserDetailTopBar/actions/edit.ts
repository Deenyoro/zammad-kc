// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import type { UserQuery } from '#shared/graphql/types.ts'
import type { ConfidentTake } from '#shared/types/utils.ts'

import { openUserEditFlyout, useUserEdit } from '#desktop/entities/user/composables/useUserEdit.ts'

import type { UserInfoActionPlugin } from './types.ts'

export default <UserInfoActionPlugin>{
  key: 'edit-user',
  label: __('Edit'),
  icon: 'pencil',
  order: 100,
  permission: 'ticket.agent',
  show(user) {
    return (user as ConfidentTake<UserQuery, 'user'>)?.policy.update
  },
  initialize: useUserEdit,
  onClick: (user) => {
    if (!user) return
    openUserEditFlyout(user as ConfidentTake<UserQuery, 'user'>)
  },
}
