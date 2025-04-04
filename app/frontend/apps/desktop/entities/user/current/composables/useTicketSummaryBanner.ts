// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

import { cloneDeep } from 'lodash-es'
import { storeToRefs } from 'pinia'
import { computed } from 'vue'

import { CurrentUserDocument } from '#shared/graphql/queries/currentUser.api.ts'
import type { CurrentUserQuery } from '#shared/graphql/types.ts'
import { getApolloClient } from '#shared/server/apollo/client.ts'
import { MutationHandler } from '#shared/server/apollo/handler/index.ts'
import { useApplicationStore } from '#shared/stores/application.ts'
import { useSessionStore } from '#shared/stores/session.ts'

import { useUserCurrentTicketSummaryBannerHiddenMutation } from '#desktop/entities/user/current/graphql/mutations/userCurrentTicketSummaryBannerHidden.api.ts'

export const useTicketSummaryBanner = () => {
  const { user } = storeToRefs(useSessionStore())
  const { config } = storeToRefs(useApplicationStore())

  const apolloClient = getApolloClient()

  const isTicketSummaryFeatureEnabled = computed(
    () =>
      !!config.value?.ai_assistance_ticket_summary &&
      !!config.value?.ai_provider,
  )

  const showBanner = computed(
    () => !user.value?.preferences?.ticket_summary_banner_hidden,
  )

  const bannerVisibilityHandler = new MutationHandler(
    useUserCurrentTicketSummaryBannerHiddenMutation(),
  )

  const toggleSummaryBanner = (show?: boolean) => {
    const { cache } = apolloClient

    const currentUserCache = cache.readQuery<CurrentUserQuery>({
      query: CurrentUserDocument,
    })

    const previousUserData = cloneDeep(currentUserCache?.currentUser)

    if (currentUserCache) {
      const updatedUserData = {
        ...previousUserData,
        preferences: {
          ...previousUserData!.preferences,
          ticket_summary_banner_hidden: !show,
        },
      }

      cache.writeQuery({
        query: CurrentUserDocument,
        data: {
          currentUser: updatedUserData,
        },
      })
    }

    bannerVisibilityHandler
      .send({
        hidden: !show,
      })
      .catch(() => {
        if (!currentUserCache) return
        cache.writeQuery({
          query: CurrentUserDocument,
          data: {
            currentUser: previousUserData,
          },
        })
      })
  }

  return {
    showBanner,
    isTicketSummaryFeatureEnabled,
    toggleSummaryBanner,
    config,
  }
}
