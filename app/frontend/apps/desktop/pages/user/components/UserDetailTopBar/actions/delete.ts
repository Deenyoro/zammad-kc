// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import type { User } from '#shared/graphql/types.ts'

import { useNewBetaUi } from '#desktop/composables/useNewBetaUi.ts'

import type { UserInfoActionPlugin } from './types.ts'

export default <UserInfoActionPlugin>{
  key: 'delete-user',
  label: __('Delete'),
  icon: 'trash',
  order: 400,
  permission: ['admin.data_privacy', 'admin.user'],
  onClick: (user?: User) => {
    if (!user) return

    const { switchValue, toggleBetaUiSwitch } = useNewBetaUi()

    const url = `/#system/data_privacy/${user.internalId}`

    if (!switchValue.value) {
      window.location.href = url
      return
    }

    // Make sure to clear the beta switch flag, so the admin does not end up in redirect loop.
    toggleBetaUiSwitch(url)
  },
}
