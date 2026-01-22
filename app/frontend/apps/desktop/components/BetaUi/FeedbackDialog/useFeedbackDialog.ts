// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { useDialog } from '#desktop/components/CommonDialog/useDialog.ts'
import type { MilestoneKey } from '#desktop/types/appUsage.ts'

export const FEEDBACK_DIALOG_NAME = 'beta-ui-feedback'

export const useFeedbackDialog = () => {
  const { open } = useDialog({
    name: FEEDBACK_DIALOG_NAME,
    global: true,
    component: () => import('../FeedbackDialog/FeedbackDialog.vue'),
  })

  const openFeedbackDialog = (milestone?: MilestoneKey) => open({ milestone })

  return { openFeedbackDialog }
}
