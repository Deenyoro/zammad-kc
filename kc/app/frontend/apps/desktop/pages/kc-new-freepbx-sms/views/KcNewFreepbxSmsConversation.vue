<!-- KC: New SMS Message (FreePBX) page for the Vue 3 desktop-view.
     Mirrors the legacy kc_new_freepbx_sms_conversation.coffee page: the
     text is sent from one of the PBX's numbers through the KC PBX connector. -->

<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useRouter } from 'vue-router'

import {
  NotificationTypes,
  useNotifications,
} from '#shared/components/CommonNotifications/index.ts'

import LayoutContent from '#desktop/components/layout/LayoutContent.vue'

import { kcApiFetch, zammadApiFetch } from '#shared/composables/useKcApi.ts'

interface SmsUser {
  id: number
  name: string
  phone: string | null
  mobile: string | null
}

interface SmsNumber {
  number: string
  label: string
  channel_id: number
}

interface ZammadGroup {
  id: number
  name: string
  active: boolean
}

interface NumbersResponse {
  enabled: boolean
  numbers: SmsNumber[]
  default_number: string
}

interface SearchResponse {
  users: SmsUser[]
}

interface CreateResponse {
  id: number
  number: string
}

const router = useRouter()
const { notify } = useNotifications()

// Form state
const phoneNumber = ref('')
const body = ref('')
const groupId = ref('')
const fromNumber = ref('')
const smsEnabled = ref(true)
const skipSend = ref(false)
const customerId = ref<number | null>(null)

// Search state
const searchQuery = ref('')
const searchResults = ref<SmsUser[]>([])
const showResults = ref(false)
const selectedUser = ref<SmsUser | null>(null)

// Number & group state
const numbers = ref<SmsNumber[]>([])
const groups = ref<ZammadGroup[]>([])
const submitting = ref(false)

// Debounced search — clear on unmount to prevent stale callbacks.
let searchTimeout: ReturnType<typeof setTimeout> | null = null

onBeforeUnmount(() => {
  if (searchTimeout) {
    clearTimeout(searchTimeout)
    searchTimeout = null
  }
})

const loadNumbers = async () => {
  try {
    const data = await kcApiFetch<NumbersResponse>(
      '/conversations/freepbx_sms_numbers',
    )
    smsEnabled.value = data?.enabled !== false
    numbers.value = data?.numbers ?? []
    const preferred = numbers.value.find(
      (entry) => entry.number === data?.default_number,
    )
    if (preferred) {
      fromNumber.value = preferred.number
    } else if (numbers.value.length > 0) {
      fromNumber.value = numbers.value[0].number
    }
  } catch {
    notify({
      id: 'kc-freepbx-sms-numbers-error',
      type: NotificationTypes.Error,
      message: __('Failed to load FreePBX texting numbers.'),
    })
  }
}

const loadGroups = async () => {
  try {
    const data = await zammadApiFetch<ZammadGroup[]>('/groups')
    groups.value = Array.isArray(data) ? data.filter((g) => g.active) : []
  } catch {
    // Groups are optional — the backend uses the channel default.
  }
}

const onSearchInput = () => {
  if (searchTimeout) clearTimeout(searchTimeout)

  if (searchQuery.value.length < 2) {
    searchResults.value = []
    showResults.value = false
    return
  }

  searchTimeout = setTimeout(async () => {
    try {
      const data = await kcApiFetch<SearchResponse>(
        `/conversations/sms_users?query=${encodeURIComponent(searchQuery.value)}`,
      )
      searchResults.value = data.users
      showResults.value = data.users.length > 0
    } catch {
      searchResults.value = []
      showResults.value = false
      notify({
        id: 'kc-freepbx-sms-search-error',
        type: NotificationTypes.Error,
        message: __('Failed to search recipients.'),
      })
    }
  }, 300)
}

// Normalize a phone number to E.164 format (+1XXXXXXXXXX for US numbers).
// Mirrors the legacy CoffeeScript normalizePhone() exactly.
const normalizePhone = (raw: string): string => {
  if (!raw) return ''
  const digits = raw.replace(/[^\d]/g, '')
  if (digits.length < 7) return ''
  if (digits.length === 10) return `+1${digits}`
  if (digits.length === 11 && digits[0] === '1') return `+${digits}`
  return `+${digits}`
}

interface SearchResultEntry {
  userId: number
  userName: string
  phone: string
  label: string
}

// Build separate entries for phone vs. mobile (matching legacy per-number selection).
const searchResultEntries = computed<SearchResultEntry[]>(() => {
  const entries: SearchResultEntry[] = []
  for (const user of searchResults.value) {
    if (user.phone) {
      const suffix = user.mobile && user.mobile !== user.phone ? ' (phone)' : ''
      entries.push({
        userId: user.id,
        userName: user.name,
        phone: user.phone,
        label: `${user.name}${suffix}`,
      })
    }
    if (user.mobile && user.mobile !== user.phone) {
      const suffix = user.phone ? ' (mobile)' : ''
      entries.push({
        userId: user.id,
        userName: user.name,
        phone: user.mobile,
        label: `${user.name}${suffix}`,
      })
    }
  }
  return entries
})

const MAX_GROUP_RECIPIENTS = 10

// Split the phone field into normalized, de-duplicated E.164 numbers.
// Several numbers (comma / semicolon / newline separated) make a group text.
// Returns null when any part is not a usable number.
const parsePhones = (raw: string): string[] | null => {
  const result: string[] = []
  for (const part of raw.split(/[,;\n]+/)) {
    const trimmed = part.trim()
    if (!trimmed) continue
    const normalized = normalizePhone(trimmed)
    if (!normalized) return null
    if (!result.includes(normalized)) result.push(normalized)
  }
  return result
}

const recipientCount = computed(() => parsePhones(phoneNumber.value)?.length ?? 0)

// Picking a recipient appends to the list so a group text is built by
// searching several times. The first recipient becomes the ticket customer.
const selectEntry = (entry: SearchResultEntry) => {
  const current = parsePhones(phoneNumber.value) ?? []
  const normalized = normalizePhone(entry.phone)
  if (normalized && !current.includes(normalized)) current.push(normalized)
  phoneNumber.value = current.join(', ')
  if (current.length === 1) {
    selectedUser.value = { id: entry.userId, name: entry.userName, phone: entry.phone, mobile: null }
    customerId.value = entry.userId
  }
  searchQuery.value = ''
  searchResults.value = []
  showResults.value = false
}

const clearSelection = () => {
  selectedUser.value = null
  customerId.value = null
  phoneNumber.value = ''
  searchQuery.value = ''
}

const canSubmit = computed(() => {
  return (
    phoneNumber.value.trim() !== '' &&
    body.value.trim() !== '' &&
    fromNumber.value !== '' &&
    smsEnabled.value
  )
})

const submitLabel = computed(() => {
  return skipSend.value ? __('Create Ticket') : __('Send SMS')
})

const submit = async () => {
  if (!canSubmit.value || submitting.value) return

  // Normalize every number to E.164 before sending; several = group text
  const recipients = parsePhones(phoneNumber.value)
  if (!recipients || recipients.length === 0) {
    notify({
      id: 'kc-freepbx-sms-phone-invalid',
      type: NotificationTypes.Error,
      message: __('Please enter a valid phone number.'),
    })
    return
  }
  if (recipients.length > MAX_GROUP_RECIPIENTS) {
    notify({
      id: 'kc-freepbx-sms-phone-too-many',
      type: NotificationTypes.Error,
      message: __('A group text can have at most 10 recipients.'),
    })
    return
  }
  const normalized = recipients[0]
  // Update the field so the user sees the corrected format
  phoneNumber.value = recipients.join(', ')

  submitting.value = true
  try {
    const result = await kcApiFetch<CreateResponse>('/conversations/freepbx_sms', {
      method: 'POST',
      body: JSON.stringify({
        phone_number: normalized,
        phone_numbers: recipients,
        body: body.value.trim(),
        group_id: groupId.value || undefined,
        customer_id: customerId.value || undefined,
        from_number: fromNumber.value,
        skip_send: skipSend.value,
      }),
    })

    notify({
      id: 'kc-freepbx-sms-created',
      type: NotificationTypes.Success,
      message: __('SMS conversation created.'),
    })

    router.push(`/tickets/${result.id}`)
  } catch (error) {
    notify({
      id: 'kc-freepbx-sms-error',
      type: NotificationTypes.Error,
      message:
        (error as Error).message ||
        __('Failed to create SMS conversation.'),
    })
  } finally {
    submitting.value = false
  }
}

// Load numbers and groups on mount.
loadNumbers()
loadGroups()

watch(searchQuery, onSearchInput)
</script>

<template>
  <LayoutContent
    :breadcrumb-items="[{ label: __('New SMS Message (FreePBX)'), route: '/kc/new_freepbx_sms' }]"
    width="narrow"
  >
    <div class="space-y-4">
      <h1 class="text-xl font-medium">
        {{ $t('New SMS Message (FreePBX)') }}
      </h1>

      <p v-if="!smsEnabled" class="text-sm text-red-500">
        {{ $t('FreePBX text messaging is switched off. An admin can enable it under KC Extensions > FreePBX.') }}
      </p>

      <!-- Recipient search -->
      <div class="relative">
        <label class="mb-1 block text-sm font-medium">
          {{ $t('Recipient') }}
        </label>
        <div class="flex gap-2">
          <input
            v-model="searchQuery"
            type="text"
            :placeholder="$t('Search by name or phone...')"
            class="w-full rounded border border-neutral-300 bg-white px-3 py-2 text-sm dark:border-neutral-600 dark:bg-neutral-800"
          />
          <button
            v-if="selectedUser || phoneNumber"
            type="button"
            class="text-sm text-red-500 hover:text-red-700"
            @click="clearSelection"
          >
            {{ $t('Clear') }}
          </button>
        </div>
        <div
          v-if="showResults && searchResultEntries.length > 0"
          class="absolute z-10 mt-1 w-full rounded border border-neutral-300 bg-white shadow-lg dark:border-neutral-600 dark:bg-neutral-800"
        >
          <button
            v-for="(entry, idx) in searchResultEntries"
            :key="`${entry.userId}-${idx}`"
            type="button"
            class="block w-full px-3 py-2 text-left text-sm hover:bg-blue-50 dark:hover:bg-neutral-700"
            @click="selectEntry(entry)"
          >
            <div class="font-medium">{{ entry.label }}</div>
            <div class="text-xs text-neutral-500">
              {{ entry.phone }}
            </div>
          </button>
        </div>
      </div>

      <!-- Phone number -->
      <div>
        <label class="mb-1 block text-sm font-medium">
          {{ $t('Phone Number') }}
        </label>
        <input
          v-model="phoneNumber"
          type="text"
          autocomplete="off"
          :placeholder="$t('+1234567890, +1987654321')"
          class="w-full rounded border border-neutral-300 bg-white px-3 py-2 text-sm dark:border-neutral-600 dark:bg-neutral-800"
        />
        <p class="mt-1 text-xs text-neutral-500">
          {{ $t('Separate several numbers with commas to send one group text (up to 10 recipients). Replies from any member land on the same ticket.') }}
        </p>
        <p v-if="recipientCount > 1" class="mt-1 text-xs font-medium">
          {{ $t('Group text to %s recipients', recipientCount) }}
        </p>
      </div>

      <!-- From number -->
      <div>
        <label class="mb-1 block text-sm font-medium">
          {{ $t('From Number') }}
        </label>
        <select
          v-if="numbers.length > 0"
          v-model="fromNumber"
          class="w-full rounded border border-neutral-300 bg-white px-3 py-2 text-sm dark:border-neutral-600 dark:bg-neutral-800"
        >
          <option
            v-for="entry in numbers"
            :key="entry.number"
            :value="entry.number"
          >
            {{ entry.label || entry.number }}
          </option>
        </select>
        <p v-else class="text-xs text-neutral-500">
          {{ $t('The PBX connector has not reported any texting numbers yet. Use Test on the FreePBX connection to refresh them.') }}
        </p>
      </div>

      <!-- Group selector -->
      <div v-if="groups.length > 0">
        <label class="mb-1 block text-sm font-medium">
          {{ $t('Group') }}
        </label>
        <select
          v-model="groupId"
          class="w-full rounded border border-neutral-300 bg-white px-3 py-2 text-sm dark:border-neutral-600 dark:bg-neutral-800"
        >
          <option value="">
            {{ $t('Default') }}
          </option>
          <option
            v-for="group in groups"
            :key="group.id"
            :value="String(group.id)"
          >
            {{ group.name }}
          </option>
        </select>
      </div>

      <!-- Message body -->
      <div>
        <label class="mb-1 block text-sm font-medium">
          {{ $t('Message') }}
        </label>
        <textarea
          v-model="body"
          rows="5"
          :placeholder="$t('Type your SMS message...')"
          class="w-full rounded border border-neutral-300 bg-white px-3 py-2 text-sm dark:border-neutral-600 dark:bg-neutral-800"
        />
      </div>

      <!-- Skip send toggle -->
      <div class="flex items-center gap-2">
        <input
          id="kc-freepbx-skip-send"
          v-model="skipSend"
          type="checkbox"
          class="rounded"
        />
        <label for="kc-freepbx-skip-send" class="text-sm">
          {{ $t("Don't send initial SMS (create ticket only)") }}
        </label>
      </div>

      <!-- Submit -->
      <div>
        <button
          type="button"
          :disabled="!canSubmit || submitting"
          class="rounded bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
          @click="submit"
        >
          {{ submitting ? $t('Creating...') : submitLabel }}
        </button>
      </div>
    </div>
  </LayoutContent>
</template>
