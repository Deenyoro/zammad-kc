// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { TicketTaskbarTabAttributesFragmentDoc } from '#shared/entities/ticket/graphql/fragments/ticketTaskbarTabAttributes.api.ts'
import { EnumTaskbarEntity } from '#shared/graphql/types.ts'

import type { UserTaskbarTabPlugin } from '#desktop/components/UserTaskbarTabs/types.ts'

import Search from '../Search/Search.vue'

const entityType = 'Search'

export default <UserTaskbarTabPlugin>{
  type: EnumTaskbarEntity.Search,
  component: Search,
  entityType,
  entityDocument: TicketTaskbarTabAttributesFragmentDoc,
  buildEntityTabKey: () => entityType,
  buildTaskbarTabParams: (entityInternalId: string) => {
    return {
      search: entityInternalId,
    }
  },
  buildTaskbarTabLink: (entity) => {
    console.log('search entity', entity)
    // :TODO add search term and query for entity
    return '/search'
    // return `/search/${entity}`
  },
  confirmTabRemove: true,
}
