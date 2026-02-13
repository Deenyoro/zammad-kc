<!-- KC: Content component for the scheduled replies sidebar.
     Shows pending scheduled articles with cancel capability, and allows
     scheduling the current article compose form for future delivery. -->

<script lang="ts" setup>
import { computed, ref } from 'vue'

import {
  NotificationTypes,
  useNotifications,
} from '#shared/components/CommonNotifications/index.ts'
import { i18n } from '#shared/i18n/index.ts'
import type { ObjectLike } from '#shared/types/utils.ts'

import CommonLoader from '#desktop/components/CommonLoader/CommonLoader.vue'
import TicketSidebarContent from '#desktop/pages/ticket/components/TicketSidebar/TicketSidebarContent.vue'
import { useTicketInformation } from '#desktop/pages/ticket/composables/useTicketInformation.ts'
import type { TicketSidebarContentProps } from '#desktop/pages/ticket/types/sidebar.ts'

import {
  useKcScheduledReplies,
  articleTypeLabel,
} from './useKcScheduledReplies.ts'

const props = defineProps<TicketSidebarContentProps>()

const persistentStates = defineModel<ObjectLike>({ required: true })

const { notify } = useNotifications()
const { ticketInternalId, isTicketEditable } = useTicketInformation()

const {
  scheduledArticles,
  loading,
  createScheduledArticle,
  cancelScheduledArticle,
} = useKcScheduledReplies(ticketInternalId)

const scheduledAt = ref('')
const scheduling = ref(false)

const isEditable = computed(() => isTicketEditable.value)

const minDateTime = computed(() => {
  const now = new Date()
  now.setMinutes(now.getMinutes() + 1)
  return now.toISOString().slice(0, 16)
})

const formatDateTime = (isoString: string): string => {
  try {
    return i18n.dateTime(isoString, 'long')
  } catch {
    return isoString
  }
}

const stripHtml = (html: string): string => {
  try {
    const doc = new DOMParser().parseFromString(html, 'text/html')
    return doc.body.textContent?.trim() || ''
  } catch {
    return html.replace(/<[^>]*>/g, '').trim()
  }
}

const truncate = (text: string, maxLength = 200): string => {
  if (text.length <= maxLength) return text
  return `${text.slice(0, maxLength)}...`
}

const formatRecipient = (value: unknown): string | undefined => {
  if (!value) return undefined
  if (typeof value === 'string') return value
  if (Array.isArray(value)) {
    return value
      .filter((v): v is string => typeof v === 'string')
      .join(', ')
  }
  return undefined
}

const getArticleFormData = (): Record<string, unknown> | null => {
  if (!props.context.formValues) return null

  const fv = props.context.formValues
  // Handle both nested (article.body) and flat (body) form structures —
  // the actual shape depends on whether the ticket detail form nests
  // article fields or keeps them top-level.
  const article = (fv.article as Record<string, unknown>) || {}

  const body = article.body || fv.body || ''
  if (!body) return null

  return {
    body,
    type: article.articleType || fv.articleType || 'note',
    to: formatRecipient(article.to || fv.to),
    cc: formatRecipient(article.cc || fv.cc),
    subject: article.subject || fv.subject,
    internal: article.internal ?? fv.internal ?? false,
    content_type: article.contentType || fv.contentType || 'text/html',
  }
}

const canSchedule = computed(() => {
  if (!scheduledAt.value) return false
  const selectedTime = new Date(scheduledAt.value)
  return selectedTime > new Date()
})

const handleSchedule = async () => {
  if (!canSchedule.value || scheduling.value) return

  const articleData = getArticleFormData()
  if (!articleData) {
    notify({
      id: 'kc-scheduled-empty-body',
      type: NotificationTypes.Error,
      message: __('Please compose a message before scheduling.'),
    })
    return
  }

  scheduling.value = true
  try {
    await createScheduledArticle({
      article_data: articleData,
      scheduled_at: new Date(scheduledAt.value).toISOString(),
    })
    scheduledAt.value = ''
  } catch {
    // error notification handled by composable
  } finally {
    scheduling.value = false
  }
}

const handleCancel = async (articleId: number) => {
  await cancelScheduledArticle(articleId)
}
</script>

<template>
  <TicketSidebarContent
    v-model="persistentStates.scrollPosition"
    :title="sidebarPlugin.title"
    :icon="sidebarPlugin.icon"
  >
    <CommonLoader :loading="loading">
      <!-- Pending scheduled replies list -->
      <div v-if="scheduledArticles.length > 0" class="space-y-3">
        <div
          v-for="item in scheduledArticles"
          :key="item.id"
          class="rounded border border-neutral-200 p-2 dark:border-neutral-700"
        >
          <div class="flex items-center justify-between">
            <span class="text-xs font-medium">{{
              formatDateTime(item.scheduled_at)
            }}</span>
            <span
              class="rounded bg-blue-100 px-1.5 py-0.5 text-xs text-blue-800 dark:bg-blue-900/40 dark:text-blue-200"
            >
              {{ articleTypeLabel(item.article_data?.type) }}
            </span>
          </div>
          <div
            v-if="item.article_data?.to"
            class="mt-1 text-xs text-neutral-500"
          >
            {{ $t('To') }}: {{ item.article_data.to }}
          </div>
          <div
            v-if="item.article_data?.cc"
            class="mt-1 text-xs text-neutral-500"
          >
            {{ $t('CC') }}: {{ item.article_data.cc }}
          </div>
          <div
            v-if="item.article_data?.body"
            class="mt-1 text-xs text-neutral-500"
          >
            {{ truncate(stripHtml(item.article_data.body)) }}
          </div>
          <button
            v-if="isEditable"
            type="button"
            class="mt-1.5 text-xs text-red-500 hover:text-red-700"
            @click="handleCancel(item.id)"
          >
            {{ $t('Cancel Scheduled Reply') }}
          </button>
        </div>
      </div>

      <div v-else class="text-sm text-neutral-500">
        {{ $t('No scheduled replies.') }}
      </div>

      <!-- Schedule current reply -->
      <div
        v-if="isEditable"
        class="mt-4 border-t border-neutral-200 pt-3 dark:border-neutral-700"
      >
        <label class="mb-2 block text-xs font-medium">{{
          $t('Schedule Current Reply')
        }}</label>
        <div class="space-y-2">
          <input
            v-model="scheduledAt"
            type="datetime-local"
            :min="minDateTime"
            class="w-full rounded border border-neutral-300 bg-white px-2 py-1 text-sm dark:border-neutral-600 dark:bg-neutral-800"
          />
          <button
            type="button"
            class="w-full rounded bg-blue-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="!canSchedule || scheduling"
            @click="handleSchedule"
          >
            {{ scheduling ? $t('Scheduling...') : $t('Schedule Reply') }}
          </button>
        </div>
      </div>
    </CommonLoader>
  </TicketSidebarContent>
</template>
