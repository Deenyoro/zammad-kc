// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { computed, type ComputedRef, type Ref } from 'vue'

import { useEntity } from '#shared/entities/useEntity.ts'
import type { User } from '#shared/graphql/types.ts'

export const useUserEntity = (user: Ref<User | undefined> | ComputedRef<User | undefined>) => {
  const entity = useEntity('User')

  const userDisplayName = computed(() => {
    if (!user.value) return ''

    return entity.display(user.value)
  })

  const isUserInactive = computed(() => user.value?.active === false)

  return {
    userDisplayName,
    isUserInactive,
  }
}
