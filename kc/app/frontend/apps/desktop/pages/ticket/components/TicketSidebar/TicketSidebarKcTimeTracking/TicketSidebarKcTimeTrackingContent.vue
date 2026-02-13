<!-- KC: Content component for the per-agent time tracking sidebar.
     Shows time entries grouped by agent, with add/delete controls. -->

<script lang="ts" setup>
import { computed, ref } from 'vue'

import type { ObjectLike } from '#shared/types/utils.ts'

import CommonLoader from '#desktop/components/CommonLoader/CommonLoader.vue'
import TicketSidebarContent from '#desktop/pages/ticket/components/TicketSidebar/TicketSidebarContent.vue'
import { useTicketInformation } from '#desktop/pages/ticket/composables/useTicketInformation.ts'
import type { TicketSidebarContentProps } from '#desktop/pages/ticket/types/sidebar.ts'

import { useKcTimeTracking } from './useKcTimeTracking.ts'

defineProps<TicketSidebarContentProps>()

const persistentStates = defineModel<ObjectLike>({ required: true })

const { ticketInternalId, isTicketEditable } = useTicketInformation()

const { agentGroups, total, loading, addEntry, deleteEntry } =
  useKcTimeTracking(ticketInternalId)

const MAX_VISIBLE_GROUPS = 5

const showAll = ref(false)
const showAddForm = ref(false)
const newTimeUnit = ref<number | null>(null)
const adding = ref(false)

const visibleGroups = computed(() => {
  if (showAll.value) return agentGroups.value
  return agentGroups.value.slice(0, MAX_VISIBLE_GROUPS)
})

const isEditable = computed(() => isTicketEditable.value)

const formatTime = (minutes: number): string => {
  if (minutes >= 60) {
    const hours = Math.floor(minutes / 60)
    const mins = Math.round(minutes % 60)
    return mins > 0 ? `${hours}h ${mins}m` : `${hours}h`
  }
  return `${Math.round(minutes)}m`
}

const handleAdd = async () => {
  if (!newTimeUnit.value || newTimeUnit.value <= 0) return

  adding.value = true
  try {
    await addEntry(newTimeUnit.value)
    newTimeUnit.value = null
    showAddForm.value = false
  } catch {
    // error notification handled by composable
  } finally {
    adding.value = false
  }
}

const handleDelete = async (entryId: number) => {
  await deleteEntry(entryId)
}
</script>

<template>
  <TicketSidebarContent
    v-model="persistentStates.scrollPosition"
    :title="sidebarPlugin.title"
    :icon="sidebarPlugin.icon"
  >
    <CommonLoader :loading="loading">
      <!-- Total -->
      <div class="mb-3 text-sm">
        <span class="font-medium">{{ $t('Total') }}:</span>
        {{ formatTime(total) }}
      </div>

      <!-- Agent groups -->
      <div v-if="agentGroups.length > 0" class="space-y-3">
        <div
          v-for="group in visibleGroups"
          :key="String(group.agentId)"
          class="rounded border border-neutral-200 p-2 dark:border-neutral-700"
        >
          <div
            class="flex items-center justify-between text-sm font-medium"
          >
            <span>{{ group.agentName }}</span>
            <span class="text-neutral-500">{{
              formatTime(group.total)
            }}</span>
          </div>
          <div class="mt-1 space-y-0.5">
            <div
              v-for="entry in group.entries"
              :key="entry.id"
              class="flex items-center justify-between text-xs text-neutral-500"
            >
              <span
                >{{ entry.type_name || '-' }} &mdash;
                {{ formatTime(entry.time_unit) }}</span
              >
              <button
                v-if="isEditable"
                type="button"
                class="text-red-400 hover:text-red-600"
                :aria-label="$t('Delete time entry')"
                @click="handleDelete(entry.id)"
              >
                &times;
              </button>
            </div>
          </div>
        </div>
      </div>

      <div v-else class="text-sm text-neutral-500">
        {{ $t('No time entries recorded.') }}
      </div>

      <!-- Show more -->
      <button
        v-if="agentGroups.length > MAX_VISIBLE_GROUPS && !showAll"
        type="button"
        class="mt-2 text-xs text-blue-600 hover:text-blue-800 dark:text-blue-400"
        @click="showAll = true"
      >
        {{ $t('Show all (%s)', String(agentGroups.length)) }}
      </button>

      <!-- Add form -->
      <div
        v-if="isEditable"
        class="mt-4 border-t border-neutral-200 pt-3 dark:border-neutral-700"
      >
        <div v-if="showAddForm" class="space-y-2">
          <div>
            <label class="mb-1 block text-xs font-medium">{{
              $t('Time (minutes)')
            }}</label>
            <input
              v-model.number="newTimeUnit"
              type="number"
              min="1"
              step="1"
              class="w-full rounded border border-neutral-300 bg-white px-2 py-1 text-sm dark:border-neutral-600 dark:bg-neutral-800"
              :placeholder="$t('Minutes')"
            />
          </div>
          <div class="flex gap-2">
            <button
              type="button"
              class="rounded bg-blue-600 px-3 py-1 text-xs text-white hover:bg-blue-700 disabled:opacity-50"
              :disabled="!newTimeUnit || newTimeUnit <= 0 || adding"
              @click="handleAdd"
            >
              {{ adding ? $t('Adding...') : $t('Add') }}
            </button>
            <button
              type="button"
              class="text-xs text-neutral-500 hover:text-neutral-700"
              @click="showAddForm = false"
            >
              {{ $t('Cancel') }}
            </button>
          </div>
        </div>
        <button
          v-else
          type="button"
          class="text-xs text-blue-600 hover:text-blue-800 dark:text-blue-400"
          @click="showAddForm = true"
        >
          + {{ $t('Add Time Entry') }}
        </button>
      </div>
    </CommonLoader>
  </TicketSidebarContent>
</template>
