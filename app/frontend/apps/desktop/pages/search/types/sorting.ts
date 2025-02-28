// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import type { EnumOrderDirection } from '#shared/graphql/types.ts'

export interface CustomSorting {
  orderBy: string
  orderDirection: EnumOrderDirection
}
