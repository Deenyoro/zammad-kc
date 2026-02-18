<!-- KC: Content component for the per-agent time tracking sidebar.
     Shows time entries grouped by agent, with add/delete controls. -->

<script lang="ts" setup>
import { computed, ref, watch } from 'vue'

import type { ObjectLike } from '#shared/types/utils.ts'

import CommonLoader from '#desktop/components/CommonLoader/CommonLoader.vue'
import TicketSidebarContent from '#desktop/pages/ticket/components/TicketSidebar/TicketSidebarContent.vue'
import { useTicketInformation } from '#desktop/pages/ticket/composables/useTicketInformation.ts'
import type { TicketSidebarContentProps } from '#desktop/pages/ticket/types/sidebar.ts'

import { useKcTimeTracking } from './useKcTimeTracking.ts'

defineProps<TicketSidebarContentProps>()

const persistentStates = defineModel<ObjectLike>({ required: true })

const { ticketInternalId, isTicketEditable } = useTicketInformation()

const {
  agentGroups,
  total,
  loading,
  agentOptions,
  typeOptions,
  addEntry,
  deleteEntry,
} = useKcTimeTracking(ticketInternalId)

const MAX_VISIBLE_GROUPS = 5

const showAll = ref(false)
const showAddForm = ref(false)
const newTimeValue = ref<number | null>(null)
const newTimeUnit = ref<'minute' | 'hour'>('minute')
const selectedAgentId = ref<string>('')
const selectedTypeId = ref<string>('')
const adding = ref(false)

// Default to the first agent when options load (matching legacy behavior where
// the browser's <select> always has the first option selected by default).
watch(agentOptions, (opts) => {
  if (opts.length > 0 && !selectedAgentId.value) {
    selectedAgentId.value = String(opts[0].id)
  }
})

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
  if (!newTimeValue.value || newTimeValue.value <= 0) return

  adding.value = true
  try {
    // Convert hours to minutes if needed (backend always stores minutes)
    const timeInMinutes =
      newTimeUnit.value === 'hour'
        ? newTimeValue.value * 60
        : newTimeValue.value

    await addEntry({
      time_unit: timeInMinutes,
      agent_id: selectedAgentId.value
        ? Number(selectedAgentId.value)
        : undefined,
      type_id: selectedTypeId.value
        ? Number(selectedTypeId.value)
        : undefined,
    })
    newTimeValue.value = null
    newTimeUnit.value = 'minute'
    selectedAgentId.value = ''
    selectedTypeId.value = ''
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
      <div class="flex flex-col gap-3">
        <!-- Total -->
        <div class="text-sm">
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
          class="text-xs text-blue-600 hover:text-blue-800 dark:text-blue-400"
          @click="showAll = true"
        >
          {{ $t('Show all (%s)', String(agentGroups.length)) }}
        </button>

        <!-- Add form -->
        <div
          v-if="isEditable"
          class="border-t border-neutral-200 pt-3 dark:border-neutral-700"
        >
          <div v-if="showAddForm" class="space-y-2">
            <!-- Agent selector -->
            <div v-if="agentOptions.length > 0">
              <label class="mb-1 block text-xs font-medium">{{
                $t('Agent')
              }}</label>
              <select
                v-model="selectedAgentId"
                class="w-full rounded border border-neutral-300 bg-white px-2 py-1 text-sm dark:border-neutral-600 dark:bg-neutral-800"
              >
                <option
                  v-for="agent in agentOptions"
                  :key="agent.id"
                  :value="String(agent.id)"
                >
                  {{ agent.name }}
                </option>
              </select>
            </div>

            <!-- Activity type selector -->
            <div v-if="typeOptions.length > 0">
              <label class="mb-1 block text-xs font-medium">{{
                $t('Activity Type')
              }}</label>
              <select
                v-model="selectedTypeId"
                class="w-full rounded border border-neutral-300 bg-white px-2 py-1 text-sm dark:border-neutral-600 dark:bg-neutral-800"
              >
                <option value="">{{ $t('None') }}</option>
                <option
                  v-for="type in typeOptions"
                  :key="type.id"
                  :value="String(type.id)"
                >
                  {{ type.name }}
                </option>
              </select>
            </div>

            <!-- Time value + unit selector -->
            <div>
              <label class="mb-1 block text-xs font-medium">{{
                $t('Time')
              }}</label>
              <div class="flex gap-1.5">
                <input
                  v-model.number="newTimeValue"
                  type="number"
                  min="0.25"
                  step="0.25"
                  class="min-w-0 flex-1 rounded border border-neutral-300 bg-white px-2 py-1 text-sm dark:border-neutral-600 dark:bg-neutral-800"
                  placeholder="0.00"
                />
                <select
                  v-model="newTimeUnit"
                  class="shrink-0 rounded border border-neutral-300 bg-white px-2 py-1 text-sm dark:border-neutral-600 dark:bg-neutral-800"
                >
                  <option value="minute">{{ $t('Minutes') }}</option>
                  <option value="hour">{{ $t('Hours') }}</option>
                </select>
              </div>
            </div>

            <div class="flex gap-2">
              <button
                type="button"
                class="rounded bg-blue-600 px-3 py-1 text-xs text-white hover:bg-blue-700 disabled:opacity-50"
                :disabled="!newTimeValue || newTimeValue <= 0 || adding"
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
      </div>
    </CommonLoader>
  </TicketSidebarContent>
</template>
