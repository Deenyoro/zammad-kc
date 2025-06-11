// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import type { FieldResolverModule } from '#shared/entities/object-attributes/types/resolver.ts'

import { FieldResolver } from '../FieldResolver.ts'

export class FieldResolverActive extends FieldResolver {
  fieldType = 'toggle'

  public fieldTypeAttributes() {
    return {
      props: {
        variants: {
          true: __('yes'),
          false: __('no'),
        },
      },
    }
  }
}

export default <FieldResolverModule>{
  type: 'active',
  resolver: FieldResolverActive,
}
