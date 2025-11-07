// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import type { UserCurrentRecentCloseListQuery } from '#shared/graphql/types.ts'

export default (): UserCurrentRecentCloseListQuery => {
  return {
    userCurrentRecentCloseList: [],
  }
}
