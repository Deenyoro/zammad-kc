// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { computed, nextTick, toRef, watch } from 'vue'
import { useRoute } from 'vue-router'

import { useAuthenticationStore } from '#shared/stores/authentication.ts'

import { useDialog } from '#desktop/components/CommonDialog/useDialog.ts'

import { useBetaUiFeedbackConsentState } from './useBetaUiFeedbackConsentState.ts'

export const DIALOG_NAME = 'beta-ui-feedback-consent'

export const useBetaUiFeedbackConsent = () => {
  const { hasFeedbackConsent } = useBetaUiFeedbackConsentState()

  const route = useRoute()

  const authenticated = toRef(useAuthenticationStore(), 'authenticated')

  const afterAuthRouteActive = computed(
    // route.name is undefined when you visit or reload the after auth phase e.g two-factor auth
    () => route.name === 'LoginAfterAuth' || route.name === 'Login' || route.name === undefined,
  )

  const { open } = useDialog({
    name: DIALOG_NAME,
    global: true,
    component: () => import('../BetaUiFeedbackConsentDialog.vue'),
  })

  const showFeedbackConsent = () =>
    nextTick(() => {
      open()
    })

  watch([afterAuthRouteActive, authenticated], ([afterAuth, isAuthenticated]) => {
    if (hasFeedbackConsent.value !== 'null' || afterAuth || !isAuthenticated) return

    showFeedbackConsent()
  })
}
