// KC: Composable for scheduled replies in the ticket sidebar.
// Fetches pending scheduled articles from the KC REST API and provides
// create / cancel operations.

import { computed, ref, watch, type Ref } from 'vue'

import {
  NotificationTypes,
  useNotifications,
} from '#shared/components/CommonNotifications/index.ts'

import { kcApiFetch } from '#shared/composables/useKcApi.ts'

export interface KcScheduledArticle {
  id: number
  ticket_id: number
  article_data: {
    body?: string
    type?: string
    to?: string
    cc?: string
    subject?: string
    internal?: boolean
    content_type?: string
  }
  ticket_attributes?: Record<string, unknown>
  scheduled_at: string
  status: string
  created_by_id: number
  created_at: string
}

interface CreateParams {
  article_data: Record<string, unknown>
  ticket_attributes?: Record<string, unknown>
  scheduled_at: string
}

const ARTICLE_TYPE_LABELS: Record<string, string> = {
  email: __('Email'),
  teams_chat_message: __('Teams Chat'),
  ringcentral_sms_message: __('RingCentral SMS'),
  note: __('Note'),
  phone: __('Phone'),
  web: __('Web'),
}

export const articleTypeLabel = (type?: string): string => {
  if (!type) return __('Note')
  return ARTICLE_TYPE_LABELS[type] || type
}

export const useKcScheduledReplies = (ticketInternalId: Ref<number>) => {
  const { notify } = useNotifications()

  const scheduledArticles = ref<KcScheduledArticle[]>([])
  const loading = ref(false)
  const available = ref(true)

  const pendingCount = computed(() => scheduledArticles.value.length)

  const loadScheduledArticles = async () => {
    if (!ticketInternalId.value) return

    loading.value = true
    try {
      const data = await kcApiFetch<KcScheduledArticle[]>(
        `/tickets/${ticketInternalId.value}/scheduled_articles`,
      )
      scheduledArticles.value = data
      available.value = true
    } catch {
      scheduledArticles.value = []
      available.value = false
    } finally {
      loading.value = false
    }
  }

  const createScheduledArticle = async (params: CreateParams) => {
    try {
      await kcApiFetch(
        `/tickets/${ticketInternalId.value}/scheduled_articles`,
        {
          method: 'POST',
          body: JSON.stringify(params),
        },
      )
      notify({
        id: 'kc-scheduled-created',
        type: NotificationTypes.Success,
        message: __('Reply scheduled successfully.'),
      })
      await loadScheduledArticles()
    } catch (error) {
      notify({
        id: 'kc-scheduled-create-error',
        type: NotificationTypes.Error,
        message:
          (error as Error).message || __('Failed to schedule reply.'),
      })
      throw error
    }
  }

  const cancelScheduledArticle = async (articleId: number) => {
    try {
      await kcApiFetch(
        `/tickets/${ticketInternalId.value}/scheduled_articles/${articleId}`,
        { method: 'DELETE' },
      )
      notify({
        id: 'kc-scheduled-cancelled',
        type: NotificationTypes.Success,
        message: __('Scheduled reply cancelled.'),
      })
      await loadScheduledArticles()
    } catch (error) {
      notify({
        id: 'kc-scheduled-cancel-error',
        type: NotificationTypes.Error,
        message:
          (error as Error).message ||
          __('Failed to cancel scheduled reply.'),
      })
    }
  }

  watch(
    ticketInternalId,
    (id) => {
      if (id) loadScheduledArticles()
    },
    { immediate: true },
  )

  return {
    scheduledArticles,
    loading,
    available,
    pendingCount,
    loadScheduledArticles,
    createScheduledArticle,
    cancelScheduledArticle,
    articleTypeLabel,
  }
}
