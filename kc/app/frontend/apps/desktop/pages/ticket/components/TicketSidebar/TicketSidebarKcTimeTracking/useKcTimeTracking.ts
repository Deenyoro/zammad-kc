// KC: Composable for per-agent time tracking in the ticket sidebar.
// Fetches time entries from the KC REST API and provides CRUD operations.

import { computed, ref, watch, type Ref } from 'vue'

import {
  NotificationTypes,
  useNotifications,
} from '#shared/components/CommonNotifications/index.ts'

import { kcApiFetch } from '#shared/composables/useKcApi.ts'

export interface KcTimeEntry {
  id: number
  time_unit: number
  type_id: number | null
  type_name: string
  agent_id: number | null
  agent_name: string
  created_at: string
}

export interface KcAgentGroup {
  agentId: number | null
  agentName: string
  total: number
  entries: KcTimeEntry[]
}

export const useKcTimeTracking = (ticketInternalId: Ref<number>) => {
  const { notify } = useNotifications()

  const entries = ref<KcTimeEntry[]>([])
  const loading = ref(false)
  const available = ref(true)

  const total = computed(() =>
    entries.value.reduce((sum, e) => sum + e.time_unit, 0),
  )

  const agentGroups = computed<KcAgentGroup[]>(() => {
    const groups: Record<string, KcAgentGroup> = {}
    for (const entry of entries.value) {
      const key = String(entry.agent_id ?? 'unknown')
      if (!groups[key]) {
        groups[key] = {
          agentId: entry.agent_id,
          agentName: entry.agent_name || '-',
          total: 0,
          entries: [],
        }
      }
      groups[key].total += entry.time_unit
      groups[key].entries.push(entry)
    }
    return Object.values(groups).sort((a, b) => b.total - a.total)
  })

  const loadEntries = async () => {
    if (!ticketInternalId.value) return

    loading.value = true
    try {
      const data = await kcApiFetch<KcTimeEntry[]>(
        `/tickets/${ticketInternalId.value}/time_entries`,
      )
      entries.value = data
      available.value = true
    } catch {
      entries.value = []
      available.value = false
    } finally {
      loading.value = false
    }
  }

  const addEntry = async (timeUnit: number) => {
    try {
      await kcApiFetch(`/tickets/${ticketInternalId.value}/time_entries`, {
        method: 'POST',
        body: JSON.stringify({ time_unit: timeUnit }),
      })
      await loadEntries()
    } catch (error) {
      notify({
        id: 'kc-time-add-error',
        type: NotificationTypes.Error,
        message: (error as Error).message || __('Failed to add time entry.'),
      })
    }
  }

  const deleteEntry = async (entryId: number) => {
    try {
      await kcApiFetch(
        `/tickets/${ticketInternalId.value}/time_entries/${entryId}`,
        { method: 'DELETE' },
      )
      await loadEntries()
    } catch (error) {
      notify({
        id: 'kc-time-delete-error',
        type: NotificationTypes.Error,
        message:
          (error as Error).message || __('Failed to delete time entry.'),
      })
    }
  }

  watch(
    ticketInternalId,
    (id) => {
      if (id) loadEntries()
    },
    { immediate: true },
  )

  return {
    entries,
    loading,
    available,
    total,
    agentGroups,
    loadEntries,
    addEntry,
    deleteEntry,
  }
}
