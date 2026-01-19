// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { computed, ref, type ComputedRef, type Ref, toRef } from 'vue'

import type {
  OrganizationUpdatesSubscriptionVariables,
  OrganizationUpdatesSubscription,
  Organization,
  OrganizationQuery,
} from '#shared/graphql/types.ts'
import { QueryHandler } from '#shared/server/apollo/handler/index.ts'
import type { GraphQLHandlerError } from '#shared/types/error.ts'
import { normalizeEdges } from '#shared/utils/helpers.ts'

import { useOrganizationQuery } from '../graphql/queries/organization.api.ts'
import { OrganizationUpdatesDocument } from '../graphql/subscriptions/organizationUpdates.api.ts'
import { useOrganizationObjectAttributesStore } from '../stores/objectAttributes.ts'

import type { WatchQueryFetchPolicy } from '@apollo/client/core'

export const useOrganizationDetail = (
  organizationId: Ref<string | undefined> | ComputedRef<string | undefined>,
  initialPageSize = 5,
  additionalPageSize = 100,
  errorCallback?: (error: GraphQLHandlerError) => boolean,
  fetchPolicy?: WatchQueryFetchPolicy,
) => {
  const fetchMembersCount = ref<number>(initialPageSize)

  const organizationQuery = new QueryHandler(
    useOrganizationQuery(
      () => ({
        organizationId: organizationId.value!,
        first: initialPageSize,
      }),
      () => ({
        enabled: Boolean(organizationId.value),
        fetchPolicy,
      }),
    ),
    {
      errorCallback,
    },
  )

  const organizationResult = organizationQuery.result()

  organizationQuery.subscribeToMore<
    OrganizationUpdatesSubscriptionVariables,
    OrganizationUpdatesSubscription
  >(() => ({
    document: OrganizationUpdatesDocument,
    variables: {
      organizationId: organizationId.value!,
      first: fetchMembersCount.value,
    },
    updateQuery: (_, { subscriptionData }) => {
      if (!subscriptionData.data?.organizationUpdates.organization)
        return null as unknown as OrganizationQuery

      return {
        organization: subscriptionData.data.organizationUpdates.organization,
      }
    },
  }))

  const loading = organizationQuery.loading()

  const organization = computed(() => organizationResult.value?.organization as Organization)

  const fetchMoreMembers = () => {
    if (!organizationId) return

    organizationQuery
      .fetchMore({
        variables: {
          first: additionalPageSize,
          after: organizationResult.value?.organization?.allMembers?.pageInfo.endCursor,
        },
        updateQuery: (previousResult, { fetchMoreResult }) => {
          if (!fetchMoreResult?.organization.allMembers) return previousResult

          const newEdges = fetchMoreResult.organization.allMembers?.edges ?? []
          const oldEdges = previousResult.organization.allMembers?.edges ?? []

          return {
            organization: {
              ...previousResult.organization,
              allMembers: {
                ...fetchMoreResult.organization.allMembers,
                edges: [...oldEdges, ...newEdges],
              },
            },
          }
        },
      })
      .then(() => {
        fetchMembersCount.value += additionalPageSize
      })
  }

  const viewScreenAttributes = toRef(useOrganizationObjectAttributesStore(), 'viewScreenAttributes')

  const organizationMembers = computed(() => normalizeEdges(organization.value?.allMembers) || [])

  return {
    loading,
    organizationQuery,
    organization,
    objectAttributes: viewScreenAttributes,
    organizationMembers,
    fetchMoreMembers,
  }
}
