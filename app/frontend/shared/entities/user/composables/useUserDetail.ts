// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { storeToRefs } from 'pinia'
import { computed, type ComputedRef, ref, type Ref } from 'vue'

import { useUserQuery } from '#shared/entities/user/graphql/queries/user.api.ts'
import { useUserObjectAttributesStore } from '#shared/entities/user/stores/objectAttributes.ts'
import { UserUpdatesDocument } from '#shared/graphql/subscriptions/userUpdates.api.ts'
import type {
  UserUpdatesSubscriptionVariables,
  UserUpdatesSubscription,
  User,
  UserQuery,
} from '#shared/graphql/types.ts'
import { QueryHandler } from '#shared/server/apollo/handler/index.ts'
import type { GraphQLHandlerError } from '#shared/types/error.ts'
import { normalizeEdges } from '#shared/utils/helpers.ts'

import type { WatchQueryFetchPolicy } from '@apollo/client/core'

export const useUserDetail = (
  userId: Ref<string | undefined> | ComputedRef<string | undefined>,
  initialPageSize = 5,
  additionalPageSize = 100,
  errorCallback?: (error: GraphQLHandlerError) => boolean,
  fetchPolicy?: WatchQueryFetchPolicy,
  hasOrganizationCounts = false,
) => {
  const fetchSecondaryOrganizationsCount = ref<number>(initialPageSize)

  const userQuery = new QueryHandler(
    useUserQuery(
      () => ({
        userId: userId.value!,
        secondaryOrganizationsCount: initialPageSize,
        hasOrganizationCounts,
      }),
      () => ({ enabled: Boolean(userId.value), fetchPolicy }),
    ),
    {
      errorCallback,
    },
  )

  const userResult = userQuery.result()

  userQuery.subscribeToMore<UserUpdatesSubscriptionVariables, UserUpdatesSubscription>(() => ({
    document: UserUpdatesDocument,
    variables: {
      userId: userId.value!,
      secondaryOrganizationsCount: fetchSecondaryOrganizationsCount.value,
      hasOrganizationCounts,
    },
    updateQuery: (_, { subscriptionData }) => {
      if (!subscriptionData.data?.userUpdates.user) return null as unknown as UserQuery

      return {
        user: subscriptionData.data.userUpdates.user,
      }
    },
  }))

  const loading = userQuery.loading()

  const user = computed(() => userResult.value?.user as User)

  const fetchMoreSecondaryOrganizations = () => {
    if (!user.value) return

    userQuery
      .fetchMore({
        variables: {
          secondaryOrganizationsCount: additionalPageSize,
          after: userResult.value?.user.secondaryOrganizations?.pageInfo.endCursor,
        },
        updateQuery: (previousResult, { fetchMoreResult }) => {
          if (!fetchMoreResult?.user.secondaryOrganizations) return previousResult

          const newEdges = fetchMoreResult.user.secondaryOrganizations?.edges ?? []
          const oldEdges = previousResult.user.secondaryOrganizations?.edges ?? []

          return {
            user: {
              ...previousResult.user,
              secondaryOrganizations: {
                ...fetchMoreResult.user.secondaryOrganizations,
                edges: [...oldEdges, ...newEdges],
              },
            },
          }
        },
      })
      .then(() => {
        fetchSecondaryOrganizationsCount.value += additionalPageSize
      })
  }

  const { viewScreenAttributes } = storeToRefs(useUserObjectAttributesStore())

  const secondaryOrganizations = computed(() => normalizeEdges(user.value?.secondaryOrganizations))

  return {
    loading,
    user,
    userQuery,
    objectAttributes: viewScreenAttributes,
    secondaryOrganizations,
    fetchMoreSecondaryOrganizations,
  }
}
