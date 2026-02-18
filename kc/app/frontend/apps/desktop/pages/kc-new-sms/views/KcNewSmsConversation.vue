<!-- KC: New SMS Conversation page for the Vue 3 desktop-view.
     Mirrors the legacy kc_new_sms_conversation.coffee page. -->

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

interface SmsChannel {
  id: number
  phone_number: string
}

interface ZammadGroup {
  id: number
  name: string
  active: boolean
}

interface ChannelsResponse {
  channels: SmsChannel[]
  default_channel_id: string
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
const channelId = ref('')
const skipSend = ref(false)
const customerId = ref<number | null>(null)

// Search state
const searchQuery = ref('')
const searchResults = ref<SmsUser[]>([])
const showResults = ref(false)
const selectedUser = ref<SmsUser | null>(null)

// Channel & group state
const channels = ref<SmsChannel[]>([])
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

const loadChannels = async () => {
  try {
    const data = await kcApiFetch<ChannelsResponse>(
      '/conversations/sms_channels',
    )
    channels.value = data.channels
    if (data.default_channel_id) {
      channelId.value = data.default_channel_id
    } else if (data.channels.length > 0) {
      channelId.value = String(data.channels[0].id)
    }
  } catch {
    notify({
      id: 'kc-sms-channels-error',
      type: NotificationTypes.Error,
      message: __('Failed to load SMS channels.'),
    })
  }
}

const loadGroups = async () => {
  try {
    const data = await zammadApiFetch<ZammadGroup[]>('/groups')
    groups.value = data.filter((g) => g.active)
  } catch {
    // Groups are optional — the backend uses the channel default.
  }
}

const onSearchInput = () => {
  if (searchTimeout) clearTimeout(searchTimeout)

  // Skip search when a user is already selected — the watch fires when
  // selectEntry() sets searchQuery to the user's name, but we don't want
  // to re-search.  Legacy CoffeeScript avoids this because programmatic
  // .val() doesn't fire DOM input events; Vue watch does.
  if (selectedUser.value) return

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
        id: 'kc-sms-search-error',
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

const selectEntry = (entry: SearchResultEntry) => {
  selectedUser.value = { id: entry.userId, name: entry.userName, phone: entry.phone, mobile: null }
  customerId.value = entry.userId
  phoneNumber.value = normalizePhone(entry.phone)
  searchQuery.value = entry.userName
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
    channelId.value !== ''
  )
})

const submitLabel = computed(() => {
  return skipSend.value ? __('Create Ticket') : __('Send SMS')
})

const submit = async () => {
  if (!canSubmit.value || submitting.value) return

  // Normalize phone to E.164 before sending (matches legacy behavior)
  const normalized = normalizePhone(phoneNumber.value.trim())
  if (!normalized) {
    notify({
      id: 'kc-sms-phone-invalid',
      type: NotificationTypes.Error,
      message: __('Please enter a valid phone number.'),
    })
    return
  }
  // Update the field so the user sees the corrected format
  phoneNumber.value = normalized

  submitting.value = true
  try {
    const result = await kcApiFetch<CreateResponse>('/conversations/sms', {
      method: 'POST',
      body: JSON.stringify({
        phone_number: normalized,
        body: body.value.trim(),
        group_id: groupId.value || undefined,
        customer_id: customerId.value || undefined,
        channel_id: Number(channelId.value),
        skip_send: skipSend.value,
      }),
    })

    notify({
      id: 'kc-sms-created',
      type: NotificationTypes.Success,
      message: __('SMS conversation created.'),
    })

    router.push(`/tickets/${result.id}`)
  } catch (error) {
    notify({
      id: 'kc-sms-error',
      type: NotificationTypes.Error,
      message:
        (error as Error).message ||
        __('Failed to create SMS conversation.'),
    })
  } finally {
    submitting.value = false
  }
}

// Load channels and groups on mount.
loadChannels()
loadGroups()

watch(searchQuery, onSearchInput)
</script>

<template>
  <LayoutContent
    :breadcrumb-items="[{ label: __('New SMS Message (RingCentral)'), route: '/kc/new_rcsms' }]"
    width="narrow"
  >
    <div class="space-y-4">
      <h1 class="text-xl font-medium">
        {{ $t('New SMS Conversation') }}
      </h1>

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
            v-if="selectedUser"
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
          type="tel"
          :placeholder="$t('+1...')"
          class="w-full rounded border border-neutral-300 bg-white px-3 py-2 text-sm dark:border-neutral-600 dark:bg-neutral-800"
        />
      </div>

      <!-- From channel -->
      <div v-if="channels.length > 0">
        <label class="mb-1 block text-sm font-medium">
          {{ $t('From Number') }}
        </label>
        <select
          v-model="channelId"
          class="w-full rounded border border-neutral-300 bg-white px-3 py-2 text-sm dark:border-neutral-600 dark:bg-neutral-800"
        >
          <option
            v-for="channel in channels"
            :key="channel.id"
            :value="String(channel.id)"
          >
            {{ channel.phone_number }}
          </option>
        </select>
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
          id="kc-skip-send"
          v-model="skipSend"
          type="checkbox"
          class="rounded"
        />
        <label for="kc-skip-send" class="text-sm">
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
