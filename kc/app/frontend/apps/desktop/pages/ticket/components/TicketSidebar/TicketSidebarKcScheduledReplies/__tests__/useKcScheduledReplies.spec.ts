// KC: unit tests for the scheduled replies composable.

import { flushPromises } from '@vue/test-utils'
import { ref } from 'vue'

import { useNotifications } from '#shared/components/CommonNotifications/index.ts'
import { kcApiFetch } from '#shared/composables/useKcApi.ts'

import { toLocalDateTimeInputValue, useKcScheduledReplies } from '../useKcScheduledReplies.ts'

vi.mock('#shared/composables/useKcApi.ts', () => ({
  kcApiFetch: vi.fn(),
}))

const kcApiFetchMock = vi.mocked(kcApiFetch)

describe('useKcScheduledReplies', () => {
  beforeEach(() => {
    kcApiFetchMock.mockReset()
    useNotifications().clearAllNotifications()
  })

  it('builds the datetime-local value from local time, not UTC', () => {
    // US Eastern: 08:05 local is 12:05 UTC.
    const date = {
      getFullYear: () => 2026,
      getMonth: () => 9,
      getDate: () => 29,
      getHours: () => 8,
      getMinutes: () => 5,
      toISOString: () => '2026-10-29T12:05:00.000Z',
    } as unknown as Date

    expect(toLocalDateTimeInputValue(date)).toBe('2026-10-29T08:05')
  })

  it('loads pending replies and counts them', async () => {
    kcApiFetchMock.mockResolvedValueOnce([
      { id: 1, ticket_id: 5, article_data: {}, scheduled_at: '', status: 'pending' },
      { id: 2, ticket_id: 5, article_data: {}, scheduled_at: '', status: 'pending' },
    ])

    const { pendingCount } = useKcScheduledReplies(ref(5))
    await flushPromises()

    expect(kcApiFetchMock).toHaveBeenCalledWith('/tickets/5/scheduled_articles')
    expect(pendingCount.value).toBe(2)
  })

  it('throws and shows an error when cancelling fails', async () => {
    kcApiFetchMock.mockResolvedValue([])
    const { cancelScheduledArticle } = useKcScheduledReplies(ref(5))
    await flushPromises()

    kcApiFetchMock.mockRejectedValueOnce(
      new Error('Only pending scheduled replies can be cancelled'),
    )

    await expect(cancelScheduledArticle(1)).rejects.toThrow(
      'Only pending scheduled replies can be cancelled',
    )

    const { notifications } = useNotifications()
    expect(notifications.value.map((n) => n.message)).toContain(
      'Only pending scheduled replies can be cancelled',
    )
  })

  it('asks the server to restore attachments into the given form', async () => {
    kcApiFetchMock.mockResolvedValue([])
    const { cancelScheduledArticle } = useKcScheduledReplies(ref(5))
    await flushPromises()

    const attachments = [{ id: 9, filename: 'a.pdf', size: '3', contentType: 'application/pdf' }]
    kcApiFetchMock.mockResolvedValueOnce({ status: 'cancelled', attachments })

    const response = await cancelScheduledArticle(1, { restoreFormId: 'f-1' })

    expect(kcApiFetchMock).toHaveBeenCalledWith(
      '/tickets/5/scheduled_articles/1?restore_form_id=f-1',
      { method: 'DELETE' },
    )
    expect(response.attachments).toEqual(attachments)
  })
})
