// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/
import { ref } from 'vue'

import renderComponent from '#tests/support/components/renderComponent.ts'
import { waitForNextTick } from '#tests/support/utils.ts'

import QuickSearchInput from '#desktop/components/QuickSearch/QuickSearchInput/QuickSearchInput.vue'

const renderQuickSearchInput = () => {
  const modelValue = ref('test')
  const searchActive = ref(false)

  const wrapper = renderComponent(QuickSearchInput, {
    vModel: {
      modelValue,
      searchActive,
    },
    router: true,
  })

  return { wrapper, modelValue, searchActive }
}

describe('QuickSearchInput', () => {
  it('models search value', async () => {
    const { wrapper } = renderQuickSearchInput()

    expect(wrapper.getByRole('searchbox')).toHaveValue('test')
  })

  it('shows clear input button when focused', async () => {
    const { wrapper } = renderQuickSearchInput()

    wrapper.getByRole('searchbox', { name: 'Search…' }).focus()

    await waitForNextTick()

    expect(
      wrapper.getByRole('button', { name: 'Reset Search' }),
    ).toBeInTheDocument()
  })

  it('emits search active when focused', () => {
    const { wrapper, searchActive } = renderQuickSearchInput()

    expect(searchActive.value).toBe(false)

    wrapper.getByRole('searchbox', { name: 'Search…' }).focus()

    expect(searchActive.value).toBe(true)
  })

  it('emits search active when focused', async () => {
    const { wrapper, searchActive } = renderQuickSearchInput()

    const searchField = wrapper.getByRole('searchbox', { name: 'Search…' })

    searchField.focus()

    expect(searchActive.value).toBe(true)

    await wrapper.events.type(wrapper.baseElement, '{escape}')

    expect(searchActive.value).toBe(false)

    expect(searchField).not.toHaveFocus()
  })

  it('allows clearing and resetting of the search input', async () => {
    const { wrapper, modelValue, searchActive } = renderQuickSearchInput()

    const searchField = wrapper.getByRole('searchbox', { name: 'Search…' })

    await wrapper.events.click(
      wrapper.getByRole('button', { name: 'Clear Search' }),
    )

    expect(modelValue.value).toBe('')
    expect(searchField).toHaveFocus()
    expect(searchActive.value).toBe(true)

    await wrapper.events.click(
      wrapper.getByRole('button', { name: 'Reset Search' }),
    )

    expect(searchActive.value).toBe(false)
  })
})
