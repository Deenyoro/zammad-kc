// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// KC: the draft of a new-conversation screen lives in its taskbar task.

import { flushPromises } from '@vue/test-utils'
import { defineComponent, h, ref, type Ref } from 'vue'

import { renderComponent } from '#tests/support/components/index.ts'

import type { TaskbarTabContext } from '#desktop/entities/user/current/types.ts'

import { kcSmsDraft, type KcDraftState } from '../drafts.ts'
import { useKcConversationDraft } from '../useKcConversationDraft.ts'

const mocks = vi.hoisted(() => ({
  kcApiFetch: vi.fn(),
  update: vi.fn(),
  remove: vi.fn(),
  stateUpdate: { callback: undefined as undefined | (() => void) },
  context: { value: undefined as undefined | Ref<TaskbarTabContext> },
}))

vi.mock('#shared/composables/useKcApi.ts', () => ({ kcApiFetch: mocks.kcApiFetch }))

vi.mock('#shared/server/apollo/handler/SubscriptionHandler.ts', () => ({
  default: class {
    onSubscribed() {
      return Promise.resolve()
    }

    onResult(callback: () => void) {
      mocks.stateUpdate.callback = callback
    }
  },
}))

vi.mock(
  '#desktop/entities/user/current/graphql/subscriptions/userCurrentTaskbarItemStateUpdates.api.ts',
  () => ({ useUserCurrentTaskbarItemStateUpdatesSubscription: vi.fn() }),
)

const TAB_KEY = 'KcNewSmsScreen-4711'

vi.mock('#desktop/entities/user/current/composables/useTaskbarTab.ts', async () => {
  const { computed: vueComputed } = await import('vue')

  const tab = {
    type: 'KcNewSmsConversationContent',
    tabEntityKey: 'KcNewSmsScreen-4711',
    taskbarTabId: 'gid://zammad/Taskbar/1',
    order: 1,
    dirty: false,
  }

  return {
    useTaskbarTab: (context: Ref<TaskbarTabContext>) => {
      mocks.context.value = context

      return {
        currentTaskbarTab: vueComputed(() => tab),
        currentTaskbarEntityKey: tab.tabEntityKey,
        currentTaskbarTabId: vueComputed(() => tab.taskbarTabId),
        currentTaskbarTabUpdate: mocks.update,
        currentTaskbarTabDelete: mocks.remove,
      }
    },
  }
})

const phoneNumber = ref('')
const body = ref('')
const skipSend = ref(false)

let draft: ReturnType<typeof useKcConversationDraft>

// One screen with a draft, the form are the refs above.
const renderDraftScreen = (apply?: (state: KcDraftState) => void) =>
  renderComponent(
    defineComponent({
      setup() {
        draft = useKcConversationDraft({
          kind: kcSmsDraft,
          collect: () => ({
            phone_number: phoneNumber.value,
            body: body.value,
            skip_send: skipSend.value,
          }),
          apply:
            apply ??
            ((state) => {
              phoneNumber.value = (state.phone_number as string) ?? ''
              body.value = (state.body as string) ?? ''
              skipSend.value = state.skip_send === true
            }),
        })

        return () => h('div', draft.restored.value ? 'restored' : 'loading')
      },
    }),
  )

const renderDraft = async (storedState: KcDraftState = {}) => {
  mocks.kcApiFetch.mockResolvedValue({ exists: true, state: storedState })

  const view = renderDraftScreen()

  await flushPromises()

  return view
}

const typeAndWait = async (value: string) => {
  body.value = value
  await flushPromises()
  vi.advanceTimersByTime(300)
}

const lastSavedState = () => mocks.update.mock.lastCall?.[1]

describe('useKcConversationDraft', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    phoneNumber.value = ''
    body.value = ''
    skipSend.value = false
    mocks.stateUpdate.callback = undefined
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('restores the stored form, the legacy UI stores it the same way', async () => {
    await renderDraft({ phone_number: '+15555550111', body: 'Stored text', skip_send: true })

    expect(mocks.kcApiFetch).toHaveBeenCalledWith(
      `/conversations/draft_state?key=${encodeURIComponent(TAB_KEY)}`,
    )
    expect(phoneNumber.value).toBe('+15555550111')
    expect(body.value).toBe('Stored text')
    expect(skipSend.value).toBe(true)

    vi.advanceTimersByTime(300)

    // nothing changed - nothing to store
    expect(mocks.update).not.toHaveBeenCalled()
  })

  it('stores nothing for an untouched draft', async () => {
    await renderDraft()

    skipSend.value = true
    await flushPromises()
    vi.advanceTimersByTime(300)

    expect(mocks.update).not.toHaveBeenCalled()
    expect(mocks.context.value?.value.formIsDirty).toBe(false)
  })

  it('stores the typed form with the legacy field names', async () => {
    await renderDraft()

    await typeAndWait('Hello')

    expect(mocks.update).toHaveBeenCalledTimes(1)
    expect(mocks.update.mock.lastCall?.[0]).toMatchObject({ dirty: true })
    expect(lastSavedState()).toEqual({ phone_number: '', body: 'Hello', skip_send: false })
    expect(mocks.context.value?.value).toMatchObject({
      formValues: { body: 'Hello' },
      formIsDirty: true,
    })

    // a cleared form is stored too, once something was stored
    await typeAndWait('')

    expect(mocks.update).toHaveBeenCalledTimes(2)
    expect(lastSavedState()).toEqual({ phone_number: '', body: '', skip_send: false })
    expect(mocks.update.mock.lastCall?.[0]).toMatchObject({ dirty: false })
  })

  it('takes over a form changed elsewhere, but not the echo of its own saves', async () => {
    await renderDraft()

    await typeAndWait('First')
    await typeAndWait('First and more')

    // The echo of the first save, read after the second one was typed.
    mocks.kcApiFetch.mockResolvedValue({
      exists: true,
      state: { phone_number: '', body: 'First', skip_send: false },
    })
    mocks.stateUpdate.callback?.()
    await flushPromises()

    expect(body.value).toBe('First and more')

    // Changed in the legacy UI.
    mocks.kcApiFetch.mockResolvedValue({
      exists: true,
      state: { phone_number: '+15555550199', body: 'From the other UI', skip_send: false },
    })
    mocks.stateUpdate.callback?.()
    await flushPromises()

    expect(phoneNumber.value).toBe('+15555550199')
    expect(body.value).toBe('From the other UI')

    vi.advanceTimersByTime(300)

    // applied, not stored back
    expect(mocks.update).toHaveBeenCalledTimes(2)
  })

  it('closes the tab once the conversation was created and stores nothing after', async () => {
    await renderDraft()

    body.value = 'Sent text'
    await flushPromises()

    draft.closeDraft()
    vi.advanceTimersByTime(300)

    expect(mocks.remove).toHaveBeenCalledTimes(1)
    expect(mocks.update).not.toHaveBeenCalled()
  })

  it('keeps the form of a draft that cannot be read', async () => {
    mocks.kcApiFetch.mockRejectedValue(new Error('offline'))

    const view = renderDraftScreen(() => {
      body.value = 'must not be applied'
    })

    await flushPromises()

    expect(view.getByText('restored')).toBeInTheDocument()
    expect(body.value).toBe('')
  })
})
