// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { useLocalStorage } from '@vueuse/core'
import { computed, toRef } from 'vue'

import { useConfirmation } from '#shared/composables/useConfirmation.ts'
import { useApplicationStore } from '#shared/stores/application.ts'
import { useSessionStore } from '#shared/stores/session.ts'

import { useBetaUiFeedbackConsentState } from './useBetaUiFeedbackConsentState.ts'

export const useBetaUi = () => {
  const user = toRef(useSessionStore(), 'user')
  const config = toRef(useApplicationStore(), 'config')

  const switchValue = useLocalStorage('beta-ui-switch', false)

  const dismissValue = useLocalStorage('beta-ui-switch-dismiss', false)

  const betaUiSwitchAvailable = computed(
    () => config.value?.ui_desktop_beta_switch && user.value?.hasBetaUiSwitchAvailable,
  )

  const betaUiSwitchEnabled = computed(() => betaUiSwitchAvailable.value && !dismissValue.value)

  const { hasFeedbackConsent } = useBetaUiFeedbackConsentState()

  const toggleBetaUiSwitch = (redirectTo = '/', skipFeedbackConsentClear = false) => {
    switchValue.value = undefined

    if (!skipFeedbackConsentClear) hasFeedbackConsent.value = undefined

    window.location.href = redirectTo
  }

  const dismissBetaUiSwitch = () => {
    const { waitForConfirmation } = useConfirmation()

    waitForConfirmation(
      __(
        'You can switch between the old and the New BETA UI at any moment in the Profile Settings > New BETA UI section.',
      ),
      {
        headerIcon: 'question-circle',
        headerTitle: __('Help'),
        buttonLabel: __('Got it'),
        hideCancelButton: true,
        fullscreen: true,
      },
      `beta-ui-dismiss-${user.value?.id}`,
    )

    dismissValue.value = true
  }

  const toggleDismissBetaUiSwitch = () => {
    dismissValue.value = !dismissValue.value
  }

  return {
    betaUiSwitchAvailable,
    betaUiSwitchEnabled,
    hasFeedbackConsent,
    switchValue,
    dismissValue,
    toggleBetaUiSwitch,
    dismissBetaUiSwitch,
    toggleDismissBetaUiSwitch,
  }
}
