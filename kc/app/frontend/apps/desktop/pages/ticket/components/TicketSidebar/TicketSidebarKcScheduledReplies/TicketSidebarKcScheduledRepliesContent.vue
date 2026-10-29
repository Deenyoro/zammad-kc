<!-- KC: Content component for the scheduled replies sidebar.
     Shows pending scheduled articles with cancel capability, and allows
     scheduling the current article compose form for future delivery. -->

<script lang="ts" setup>
import { computed, nextTick, ref, useId } from 'vue'

import {
  NotificationTypes,
  useNotifications,
} from '#shared/components/CommonNotifications/index.ts'
import { transformEditorHtml } from '#shared/components/Form/fields/FieldEditor/utils.ts'
import type { FileUploaded } from '#shared/components/Form/fields/FieldFile/types.ts'
import { getNodeByName } from '#shared/components/Form/utils.ts'
import { convertToGraphQLId } from '#shared/graphql/utils.ts'
import { i18n } from '#shared/i18n/index.ts'
import type { ObjectLike } from '#shared/types/utils.ts'

import CommonLoader from '#desktop/components/CommonLoader/CommonLoader.vue'
import TicketSidebarContent from '#desktop/pages/ticket/components/TicketSidebar/TicketSidebarContent.vue'
import { useTicketInformation } from '#desktop/pages/ticket/composables/useTicketInformation.ts'
import type { TicketSidebarContentProps } from '#desktop/pages/ticket/types/sidebar.ts'

import {
  articleTypeLabel,
  toLocalDateTimeInputValue,
  type KcRestoredAttachment,
  type KcScheduledReplies,
} from './useKcScheduledReplies.ts'

interface Props extends TicketSidebarContentProps {
  // Owned by the sidebar wrapper (it also drives the tab badge).
  replies: KcScheduledReplies
}

const props = defineProps<Props>()

const persistentStates = defineModel<ObjectLike>({ required: true })

const { notify } = useNotifications()
const { isTicketEditable, newTicketArticlePresent, form } = useTicketInformation()

const { scheduledArticles, loading, createScheduledArticle, cancelScheduledArticle } = props.replies

const scheduledAt = ref('')
const scheduledAtLabelId = useId()
const scheduling = ref(false)

const isEditable = computed(() => isTicketEditable.value)

// <input type="datetime-local"> works in the browser's local time, so min/max
// must be local "YYYY-MM-DDTHH:mm" strings (toISOString() would be UTC and
// block or allow the wrong hours). The picked value has no zone either:
// new Date(value) parses it as local time and toISOString() then sends the
// correct UTC instant - the same as the legacy datetime picker.
// Refreshed whenever the picker gets focus, so the limits do not go stale
// while the sidebar stays open.
const now = ref(new Date())
const refreshNow = () => {
  now.value = new Date()
}

const minDateTime = computed(() => {
  const min = new Date(now.value.getTime())
  min.setMinutes(min.getMinutes() + 1)
  return toLocalDateTimeInputValue(min)
})

// Server limit: 90 days ahead.
const maxDateTime = computed(() => {
  const max = new Date(now.value.getTime())
  max.setDate(max.getDate() + 90)
  return toLocalDateTimeInputValue(max)
})

const formatDateTime = (isoString: string): string => {
  try {
    return i18n.dateTime(isoString)
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

// Convert a stored recipient value (string or comma-separated string) back to
// an array for FormKit multi-select fields. Without this, FormKit iterates
// over the string's characters, creating one tag per letter.
const recipientToArray = (value: unknown): string[] => {
  if (Array.isArray(value)) return value.filter((v): v is string => typeof v === 'string')
  if (typeof value === 'string') {
    return value
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean)
  }
  return []
}

const formatRecipient = (value: unknown): string | undefined => {
  if (!value) return undefined
  if (typeof value === 'string') return value
  if (Array.isArray(value)) {
    return value.filter((v): v is string => typeof v === 'string').join(', ')
  }
  return undefined
}

const isBodyEmpty = (body: string, contentType: string): boolean => {
  if (contentType !== 'text/html') return !body.trim()
  if (/<img\b/i.test(body)) return false
  return !stripHtml(body)
}

// Read article form data from the FormRef (context.form.values), NOT from
// context.formValues which only has customer_id/organization_id.
// The form values are structured as { article: { body, articleType, ... } }.
// Body and content type are processed like upstream's processArticle
// (useTicketEdit): the content type comes from the reply editor (text/plain
// for SMS/Teams, text/html otherwise) and HTML goes through
// transformEditorHtml. Signatures are part of the editor content; inline
// images (data URIs) are extracted by the server when the reply is sent.
const getArticleFormData = (): {
  articleData: Record<string, unknown>
  attachments: { name: string; type?: string | null }[]
} | null => {
  const formRef = props.context.form
  if (!formRef?.values) return null

  const formValues = formRef.values as Record<string, unknown>
  const article = (formValues.article as Record<string, unknown>) || {}

  const contentType =
    (getNodeByName(formRef.formId, 'body')?.context?.contentType as string | undefined) ||
    'text/html'

  let body = typeof article.body === 'string' ? article.body : ''
  if (isBodyEmpty(body, contentType)) return null
  if (contentType === 'text/html') body = transformEditorHtml(body)

  const data: Record<string, unknown> = {
    body,
    type: article.articleType || 'note',
    to: formatRecipient(article.to),
    cc: formatRecipient(article.cc),
    bcc: formatRecipient(article.bcc),
    subject: article.subject,
    internal: article.internal ?? false,
    content_type: contentType,
  }

  // The server copies the selected files from this form's upload cache into
  // storage owned by the scheduled reply. The form id is kept per tab, so
  // only the files listed here are taken - never files added later.
  if (formRef.formId) {
    data.form_id = formRef.formId
  }

  const files = (article.attachments as FileUploaded[] | undefined) || []

  return {
    articleData: data,
    attachments: files.map((file) => ({ name: file.name, type: file.type })),
  }
}

const canSchedule = computed(() => {
  if (!scheduledAt.value) return false
  const selectedTime = new Date(scheduledAt.value)
  return selectedTime > new Date()
})

// Reset the compose form after successful scheduling, matching the legacy
// frontend's controller.taskReset() behavior. Hides the article reply area
// and resets the article form group to default values.
const resetComposeForm = () => {
  if (newTicketArticlePresent) {
    newTicketArticlePresent.value = false
  }

  nextTick(() => {
    const articleNode = form.value?.getNodeByName('article')
    articleNode?.reset()
  })
}

// Collect current ticket attribute changes from the form, matching the legacy
// controller.ticketParams() which captures state/owner/priority changes.
const getTicketAttributes = (): Record<string, unknown> | undefined => {
  const formRef = props.context.form
  if (!formRef?.values) return undefined

  const formValues = formRef.values as Record<string, unknown>
  // Ticket-level fields are at the top level of form values (not nested).
  // Filter out the 'article' sub-object — everything else is ticket attributes.
  const attrs: Record<string, unknown> = {}
  let hasAttrs = false
  for (const [key, value] of Object.entries(formValues)) {
    if (key === 'article') continue
    if (value !== undefined && value !== null && value !== '') {
      attrs[key] = value
      hasAttrs = true
    }
  }
  return hasAttrs ? attrs : undefined
}

const handleSchedule = async () => {
  if (!canSchedule.value || scheduling.value) return

  const formData = getArticleFormData()
  if (!formData) {
    notify({
      id: 'kc-scheduled-empty-body',
      type: NotificationTypes.Error,
      message: __('Please compose a message before scheduling.'),
    })
    return
  }

  scheduling.value = true
  try {
    const ticketAttributes = getTicketAttributes()
    await createScheduledArticle({
      article_data: formData.articleData,
      attachments: formData.attachments,
      ticket_attributes: ticketAttributes,
      scheduled_at: new Date(scheduledAt.value).toISOString(),
    })
    scheduledAt.value = ''
    resetComposeForm()
  } catch {
    // error notification handled by composable
  } finally {
    scheduling.value = false
  }
}

const handleCancel = async (articleId: number) => {
  // Confirm before canceling (matching legacy App.ControllerConfirm behavior)
  if (!window.confirm(i18n.t('Cancel this scheduled reply?'))) return
  try {
    await cancelScheduledArticle(articleId)
  } catch {
    // error notification handled by composable
  }
}

const toFormAttachment = (file: KcRestoredAttachment): FileUploaded => ({
  id: convertToGraphQLId('Store', file.id),
  name: file.filename,
  size: Number(file.size) || 0,
  type: file.contentType || 'application/octet-stream',
})

const handleEdit = async (item: (typeof scheduledArticles)['value'][number]) => {
  const articleData = item.article_data
  if (!articleData) return

  // Cancel the scheduled reply first. Only when that succeeded is it loaded
  // into the editor - otherwise it would still go out and the edited copy
  // would be a duplicate. The server copies the reply's attachments back
  // into this form's upload cache.
  let restoredAttachments: KcRestoredAttachment[] = []
  try {
    const response = await cancelScheduledArticle(item.id, {
      restoreFormId: props.context.form?.formId,
      successMessage: __('Scheduled reply cancelled and loaded into the editor.'),
    })
    restoredAttachments = response.attachments || []
  } catch {
    return // error notification handled by composable
  }

  // Open the compose area and pre-fill with scheduled article data
  if (newTicketArticlePresent) {
    newTicketArticlePresent.value = true
  }

  await nextTick()

  // Pre-fill the article form with the scheduled data
  const formRef = props.context.form
  if (formRef) {
    const articleNode = formRef.getNodeByName('article')
    if (articleNode) {
      const prefill: Record<string, unknown> = {
        body: articleData.body || '',
        articleType: articleData.type || 'note',
        internal: articleData.internal ?? false,
      }
      if (articleData.to) prefill.to = recipientToArray(articleData.to)
      if (articleData.cc) prefill.cc = recipientToArray(articleData.cc)
      if (articleData.bcc) prefill.bcc = recipientToArray(articleData.bcc)
      if (articleData.subject) prefill.subject = articleData.subject
      if (restoredAttachments.length) {
        const current =
          ((articleNode.value as Record<string, unknown> | undefined)?.attachments as
            | FileUploaded[]
            | undefined) || []
        prefill.attachments = [...current, ...restoredAttachments.map(toFormAttachment)]
      }

      articleNode.input(prefill)
    }
  }

  // Also apply ticket attribute changes if they were stored
  if (item.ticket_attributes && formRef) {
    await nextTick()
    for (const [key, value] of Object.entries(item.ticket_attributes)) {
      if (key === 'article') continue
      const node = formRef.getNodeByName(key)
      if (node && value !== undefined && value !== null) {
        node.input(value)
      }
    }
  }
}
</script>

<template>
  <TicketSidebarContent
    v-model="persistentStates.scrollPosition"
    :title="sidebarPlugin.title"
    :icon="sidebarPlugin.icon"
  >
    <CommonLoader :loading="loading">
      <div class="flex flex-col gap-3">
        <!-- Pending scheduled replies list -->
        <div v-if="scheduledArticles.length > 0" class="space-y-3">
          <div
            v-for="item in scheduledArticles"
            :key="item.id"
            class="rounded border border-neutral-200 p-2 dark:border-neutral-700"
          >
            <div class="flex items-center justify-between">
              <span class="text-xs font-medium">{{ formatDateTime(item.scheduled_at) }}</span>
              <span
                class="rounded bg-blue-100 px-1.5 py-0.5 text-xs text-blue-800 dark:bg-blue-900/40 dark:text-blue-200"
              >
                {{ articleTypeLabel(item.article_data?.type) }}
              </span>
            </div>
            <div v-if="item.article_data?.to" class="mt-1 text-xs text-neutral-500">
              {{ $t('To') }}: {{ item.article_data.to }}
            </div>
            <div v-if="item.article_data?.cc" class="mt-1 text-xs text-neutral-500">
              {{ $t('CC') }}: {{ item.article_data.cc }}
            </div>
            <div
              v-if="item.article_data?.bcc"
              class="mt-1 text-xs text-neutral-500"
            >
              {{ $t('BCC') }}: {{ item.article_data.bcc }}
            </div>
            <div
              v-if="item.article_data?.body"
              class="mt-1 text-xs text-neutral-500"
            >
              {{ truncate(stripHtml(item.article_data.body)) }}
            </div>
            <div v-if="isEditable" class="mt-1.5 flex gap-3">
              <button
                type="button"
                class="text-xs text-blue-500 hover:text-blue-700"
                @click="handleEdit(item)"
              >
                {{ $t('Edit') }}
              </button>
              <button
                type="button"
                class="text-xs text-red-500 hover:text-red-700"
                @click="handleCancel(item.id)"
              >
                {{ $t('Cancel') }}
              </button>
            </div>
          </div>
        </div>

        <div v-else class="text-sm text-neutral-500">
          {{ $t('No scheduled replies.') }}
        </div>

        <!-- Schedule current reply — only shown when compose area is open -->
        <div
          v-if="isEditable && newTicketArticlePresent"
          class="border-t border-neutral-200 pt-3 dark:border-neutral-700"
        >
          <div :id="scheduledAtLabelId" class="mb-2 text-xs font-medium">
            {{ $t('Schedule Current Reply') }}
          </div>
          <div class="space-y-2">
            <input
              v-model="scheduledAt"
              :aria-labelledby="scheduledAtLabelId"
              type="datetime-local"
              :min="minDateTime"
              :max="maxDateTime"
              class="w-full rounded border border-neutral-300 bg-white px-2 py-1 text-sm dark:border-neutral-600 dark:bg-neutral-800"
              @focus="refreshNow"
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
      </div>
    </CommonLoader>
  </TicketSidebarContent>
</template>
