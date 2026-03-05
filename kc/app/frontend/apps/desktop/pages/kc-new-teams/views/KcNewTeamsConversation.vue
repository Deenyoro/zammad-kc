<!-- KC: New Teams Chat Conversation page for the Vue 3 desktop-view.
     Mirrors the legacy kc_new_teams_conversation.coffee page. -->

<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useRouter } from 'vue-router'

import {
  NotificationTypes,
  useNotifications,
} from '#shared/components/CommonNotifications/index.ts'

import LayoutContent from '#desktop/components/layout/LayoutContent.vue'

import { kcApiFetch, zammadApiFetch } from '#shared/composables/useKcApi.ts'

interface TeamsContact {
  id: string
  display_name: string
  email: string | null
  job_title: string | null
}

interface TeamsChannel {
  id: number
  label: string
}

interface ZammadGroup {
  id: number
  name: string
  active: boolean
}

interface ChannelsResponse {
  channels: TeamsChannel[]
  default_channel_id: string
}

interface SearchResponse {
  contacts: TeamsContact[]
}

interface CreateResponse {
  id: number
  number: string
}

const router = useRouter()
const { notify } = useNotifications()

// Form state
const body = ref('')
const channelId = ref('')
const groupId = ref('')

// Search state
const searchQuery = ref('')
const searchResults = ref<TeamsContact[]>([])
const showResults = ref(false)
const selectedContact = ref<TeamsContact | null>(null)

// Channel & group state
const channels = ref<TeamsChannel[]>([])
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
      '/conversations/teams_channels',
    )
    channels.value = data?.channels ?? []
    if (data?.default_channel_id) {
      channelId.value = data.default_channel_id
    } else if (channels.value.length > 0) {
      channelId.value = String(data.channels[0].id)
    }
  } catch {
    notify({
      id: 'kc-teams-channels-error',
      type: NotificationTypes.Error,
      message: __('Failed to load Teams channels.'),
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

  // Skip search when a contact is already selected — the watch fires when
  // selectContact() sets searchQuery to the contact's name, but we don't
  // want to re-search.  Legacy CoffeeScript avoids this because programmatic
  // .val() doesn't fire DOM input events; Vue watch does.
  if (selectedContact.value) return

  if (searchQuery.value.length < 2) {
    searchResults.value = []
    showResults.value = false
    return
  }

  searchTimeout = setTimeout(async () => {
    try {
      const data = await kcApiFetch<SearchResponse>(
        `/conversations/teams_contacts?query=${encodeURIComponent(searchQuery.value)}`,
      )
      searchResults.value = data.contacts
      showResults.value = data.contacts.length > 0
    } catch {
      searchResults.value = []
      showResults.value = false
      notify({
        id: 'kc-teams-search-error',
        type: NotificationTypes.Error,
        message: __('Failed to search Teams directory.'),
      })
    }
  }, 300)
}

const selectContact = (contact: TeamsContact) => {
  selectedContact.value = contact
  searchQuery.value = contact.display_name
  showResults.value = false
}

const clearSelection = () => {
  selectedContact.value = null
  searchQuery.value = ''
}

const canSubmit = computed(() => {
  return (
    selectedContact.value !== null &&
    body.value.trim() !== '' &&
    channelId.value !== ''
  )
})

const submit = async () => {
  if (!canSubmit.value || submitting.value || !selectedContact.value) return

  submitting.value = true
  try {
    const result = await kcApiFetch<CreateResponse>('/conversations/teams', {
      method: 'POST',
      body: JSON.stringify({
        teams_user_id: selectedContact.value.id,
        display_name: selectedContact.value.display_name,
        email: selectedContact.value.email || undefined,
        body: body.value.trim(),
        group_id: groupId.value || undefined,
        channel_id: Number(channelId.value),
      }),
    })

    notify({
      id: 'kc-teams-created',
      type: NotificationTypes.Success,
      message: __('Teams conversation created.'),
    })

    router.push(`/tickets/${result.id}`)
  } catch (error) {
    notify({
      id: 'kc-teams-error',
      type: NotificationTypes.Error,
      message:
        (error as Error).message ||
        __('Failed to create Teams conversation.'),
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
    :breadcrumb-items="[
      { label: __('New Teams Chat'), route: '/kc/new-teams' },
    ]"
    width="narrow"
  >
    <div class="space-y-4">
      <h1 class="text-xl font-medium">
        {{ $t('New Teams Chat Conversation') }}
      </h1>

      <!-- Contact search -->
      <div class="relative">
        <label class="mb-1 block text-sm font-medium">
          {{ $t('Recipient') }}
        </label>
        <div class="flex gap-2">
          <input
            v-model="searchQuery"
            type="text"
            :placeholder="$t('Search Teams directory...')"
            :disabled="selectedContact !== null"
            class="w-full rounded border border-neutral-300 bg-white px-3 py-2 text-sm disabled:opacity-60 dark:border-neutral-600 dark:bg-neutral-800"
          />
          <button
            v-if="selectedContact"
            type="button"
            class="text-sm text-red-500 hover:text-red-700"
            @click="clearSelection"
          >
            {{ $t('Clear') }}
          </button>
        </div>
        <div
          v-if="showResults"
          class="absolute z-10 mt-1 w-full rounded border border-neutral-300 bg-white shadow-lg dark:border-neutral-600 dark:bg-neutral-800"
        >
          <button
            v-for="contact in searchResults"
            :key="contact.id"
            type="button"
            class="block w-full px-3 py-2 text-left text-sm hover:bg-blue-50 dark:hover:bg-neutral-700"
            @click="selectContact(contact)"
          >
            <div class="font-medium">{{ contact.display_name }}</div>
            <div class="text-xs text-neutral-500">
              <span v-if="contact.email">{{ contact.email }}</span>
              <span v-if="contact.email && contact.job_title">
                &middot;
              </span>
              <span v-if="contact.job_title">{{ contact.job_title }}</span>
            </div>
          </button>
        </div>
      </div>

      <!-- Selected contact info -->
      <div
        v-if="selectedContact"
        class="rounded border border-blue-200 bg-blue-50 p-3 text-sm dark:border-blue-800 dark:bg-blue-900/20"
      >
        <div class="font-medium">{{ selectedContact.display_name }}</div>
        <div v-if="selectedContact.email" class="text-neutral-500">
          {{ selectedContact.email }}
        </div>
        <div v-if="selectedContact.job_title" class="text-neutral-500">
          {{ selectedContact.job_title }}
        </div>
      </div>

      <!-- From channel -->
      <div v-if="channels.length > 0">
        <label class="mb-1 block text-sm font-medium">
          {{ $t('From Account') }}
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
            {{ channel.label }}
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
          :placeholder="$t('Type your message...')"
          class="w-full rounded border border-neutral-300 bg-white px-3 py-2 text-sm dark:border-neutral-600 dark:bg-neutral-800"
        />
      </div>

      <!-- Submit -->
      <div>
        <button
          type="button"
          :disabled="!canSubmit || submitting"
          class="rounded bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
          @click="submit"
        >
          {{ submitting ? $t('Creating...') : $t('Send Message') }}
        </button>
      </div>
    </div>
  </LayoutContent>
</template>
