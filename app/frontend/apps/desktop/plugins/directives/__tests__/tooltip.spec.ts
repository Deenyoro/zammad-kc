// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { fireEvent, waitFor } from '@testing-library/vue'
import { describe, vi } from 'vitest'

import renderComponent from '#tests/support/components/renderComponent.ts'
import { mockLocale } from '#tests/support/mock-locale.ts'

vi.mock('#shared/composables/useTouchDevice.ts', () => ({
  useTouchDevice: vi.fn().mockReturnValue({ isTouchDevice: { value: true } }),
}))

describe('TooltipDirective', () => {
  describe('on non-touch device', () => {
    it('should show/hide tooltip on hover', async () => {
      const wrapper = renderComponent({
        template: `
          <div v-tooltip="'Hello, Tooltip'">Foo Test World</div>
         `,
      })

      await wrapper.events.hover(wrapper.getByText('Foo Test World'))

      await waitFor(() => expect(wrapper.queryByText('Hello, Tooltip')).toBeInTheDocument())

      await wrapper.events.unhover(wrapper.getByText('Foo Test World'))

      await waitFor(() => {
        expect(wrapper.queryByText('Hello, Tooltip')).not.toBeInTheDocument()
      })
    })

    it('has accessibility attribute', async () => {
      const wrapper = renderComponent({
        template: `
        <div v-tooltip="'Hello, Tooltip'">Foo Test World</div>
      `,
      })
      await waitFor(() => expect(wrapper.queryByLabelText('Hello, Tooltip')).toBeInTheDocument())
    })

    it('should hide tooltip on scroll', async () => {
      const wrapper = renderComponent({
        template: `
        <div v-tooltip="'Hello, Tooltip'">Foo Test World</div>
      `,
      })

      await wrapper.events.hover(wrapper.getByText('Foo Test World'))

      await waitFor(() => expect(wrapper.queryByText('Hello, Tooltip')).toBeInTheDocument())

      window.dispatchEvent(new Event('scroll'))

      await waitFor(() => expect(wrapper.queryByText('Hello, Tooltip')).not.toBeInTheDocument())
    })
  })

  describe('on touch device', () => {
    it('should hide tooltip on first touch', async () => {
      const wrapper = renderComponent({
        template: `
        <div v-tooltip="'Hello, Tooltip'">Foo Test World</div>
      `,
      })

      await fireEvent.touchStart(wrapper.getByText('Foo Test World'))

      await waitFor(() => {
        expect(wrapper.queryByText('Hello, Tooltip')).toBeInTheDocument()
      })

      await fireEvent.touchStart(wrapper.getByText('Foo Test World'))
      await fireEvent.touchEnd(wrapper.getByText('Foo Test World'))

      await waitFor(() => expect(wrapper.queryByText('Hello, Tooltip')).not.toBeInTheDocument())
    })

    it('updated tooltip locale', async () => {
      const translationSpy = mockLocale('Hello, Tooltip', 'Hola, Tooltip')

      const wrapper = renderComponent({
        template: `
      <div v-tooltip="$t('Hello, Tooltip')">Foo Test World</div>
    `,
      })

      await wrapper.events.hover(wrapper.getByText('Foo Test World'))

      await waitFor(() => {
        expect(wrapper.queryByText('Hola, Tooltip')).toBeInTheDocument()
        expect(wrapper.getByLabelText('Hola, Tooltip')).toBeInTheDocument()
      })

      expect(translationSpy).toHaveBeenCalledOnce()
    })
  })
})
