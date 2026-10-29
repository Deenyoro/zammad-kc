// KC: Composable for scheduled replies in the ticket sidebar.
// Fetches pending scheduled articles from the KC REST API and provides
// create / cancel operations. One instance is created by the sidebar
// wrapper (for the tab badge) and passed to the content component.

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
    bcc?: string
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
  // Files selected in the compose form; the server copies only these from
  // the form's upload cache into storage owned by the scheduled reply.
  attachments?: { name: string; type?: string | null }[]
}

export interface KcRestoredAttachment {
  id: number
  filename: string
  size: string | number
  contentType?: string
}

interface CancelOptions {
  // Form id to copy the reply's attachments back into ("Edit").
  restoreFormId?: string
  successMessage?: string
}

interface CancelResponse {
  status?: string
  attachments?: KcRestoredAttachment[]
}

const ARTICLE_TYPE_LABELS: Record<string, string> = {
  email: __('Email'),
  teams_chat_message: __('Teams Chat'),
  ringcentral_sms_message: __('RingCentral SMS'),
  freepbx_sms_message: __('FreePBX SMS'),
  note: __('Note'),
  phone: __('Phone'),
  web: __('Web'),
}

export const articleTypeLabel = (type?: string): string => {
  if (!type) return __('Note')
  return ARTICLE_TYPE_LABELS[type] || type
}

// Local "YYYY-MM-DDTHH:mm" value for <input type="datetime-local"> (which
// has no time zone and works in the browser's local time).
export const toLocalDateTimeInputValue = (date: Date): string => {
  const pad = (value: number) => String(value).padStart(2, '0')
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`
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
      scheduledArticles.value = Array.isArray(data) ? data : []
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
      await kcApiFetch(`/tickets/${ticketInternalId.value}/scheduled_articles`, {
        method: 'POST',
        body: JSON.stringify(params),
      })
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
        message: (error as Error).message || __('Failed to schedule reply.'),
      })
      throw error
    }
  }

  // Throws when cancelling failed (after showing an error notification), so
  // callers such as "Edit" never continue with a reply that is still pending.
  const cancelScheduledArticle = async (
    articleId: number,
    options: CancelOptions = {},
  ): Promise<CancelResponse> => {
    let response: CancelResponse
    try {
      const query = options.restoreFormId
        ? `?restore_form_id=${encodeURIComponent(options.restoreFormId)}`
        : ''
      response = await kcApiFetch<CancelResponse>(
        `/tickets/${ticketInternalId.value}/scheduled_articles/${articleId}${query}`,
        { method: 'DELETE' },
      )
    } catch (error) {
      notify({
        id: 'kc-scheduled-cancel-error',
        type: NotificationTypes.Error,
        message: (error as Error).message || __('Failed to cancel scheduled reply.'),
      })
      // The list may be stale (e.g. the reply was sent meanwhile).
      await loadScheduledArticles()
      throw error
    }

    notify({
      id: 'kc-scheduled-cancelled',
      type: NotificationTypes.Success,
      message: options.successMessage || __('Scheduled reply cancelled.'),
    })
    await loadScheduledArticles()
    return response || {}
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

export type KcScheduledReplies = ReturnType<typeof useKcScheduledReplies>
