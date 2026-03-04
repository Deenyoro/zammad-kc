// KC: Add a BCC field to the email article compose form in the Vue desktop-view.
//
// This FormKit global plugin is auto-discovered via import.meta.glob in
// app/frontend/shared/form/index.ts.
//
// Approach:
//   1. Intercept the CC recipient node's lifecycle (mount/destroy)
//   2. Build a standalone BCC text input with matching Tailwind classes
//   3. Store the BCC value on window.__kcBccValue for processArticle to read
//   4. Cleanup DOM and value when CC unmounts (article type changed away from email)
//
// We intentionally avoid creating a programmatic FormKit node because FormKit's
// library plugin crashes when it can't resolve the type definition for a
// headless node. The window bridge is simple and reliable.

import type { FormKitNode } from '@formkit/core'

declare global {
  interface Window {
    __kcBccValue?: string
  }
}

const KC_BCC_ATTR = 'data-kc-bcc-field'

const buildBccField = (): { container: HTMLElement; input: HTMLInputElement } => {
  // Outer — matches formkit-outer structure, spans full width
  const container = document.createElement('div')
  container.setAttribute(KC_BCC_ATTR, 'true')
  container.className = 'formkit-outer'
  container.setAttribute('data-type', 'text')

  // Block
  const block = document.createElement('div')
  block.className = 'formkit-block flex items-end'

  // Wrapper
  const wrapper = document.createElement('div')
  wrapper.className = 'formkit-wrapper flex-grow'

  // Label — matches CC label classes exactly
  const label = document.createElement('label')
  label.className =
    'formkit-label mb-1 block text-sm text-gray-100 dark:text-neutral-400'
  label.textContent = 'BCC'

  // Inner
  const inner = document.createElement('div')
  inner.className = 'formkit-inner rounded-lg text-sm w-full'

  // Input container — matches the formkit-input wrapper with hover/focus outlines
  const inputWrap = document.createElement('div')
  inputWrap.className = [
    'flex min-h-10 items-center',
    'formkit-input rounded-lg',
    'bg-blue-200 dark:bg-gray-700',
    'hover:outline-1 hover:-outline-offset-1 hover:outline-blue-600',
    'focus-within:outline-1 focus-within:-outline-offset-1 focus-within:outline-blue-800',
    'dark:hover:outline-blue-900 dark:focus-within:outline-blue-800',
  ].join(' ')

  // Actual text input — no pointer-events-none, fully interactive
  const input = document.createElement('input')
  input.type = 'text'
  input.placeholder = 'Add BCC recipients (comma-separated)'
  input.autocomplete = 'off'
  input.className =
    'w-full bg-transparent px-2.5 py-2 text-sm text-black outline-none dark:text-white'

  inputWrap.appendChild(input)
  inner.appendChild(inputWrap)
  wrapper.appendChild(label)
  wrapper.appendChild(inner)
  block.appendChild(wrapper)
  container.appendChild(block)

  return { container, input }
}

const kcBccField = (node: FormKitNode) => {
  // Only intercept CC input fields
  if (node.name !== 'cc' || node.type !== 'input') return

  let bccContainer: HTMLElement | null = null

  node.on('mounted', () => {
    requestAnimationFrame(() => {
      // Find the CC field's outer wrapper via its ID
      const ccEl = document.getElementById(node.props.id)
      if (!ccEl) return

      const ccOuter = ccEl.closest('.formkit-outer') as HTMLElement
      if (!ccOuter) return

      // Don't create if BCC already exists in the DOM
      if (ccOuter.parentElement?.querySelector(`[${KC_BCC_ATTR}]`)) return

      // Build and insert BCC field after CC
      const { container, input } = buildBccField()
      bccContainer = container
      ccOuter.after(bccContainer)

      // Restore value if one was previously entered
      if (window.__kcBccValue) {
        input.value = window.__kcBccValue
      }

      // Sync input → window bridge
      input.addEventListener('input', () => {
        window.__kcBccValue = input.value
      })
      input.addEventListener('change', () => {
        window.__kcBccValue = input.value
      })
    })
  })

  node.on('destroying', () => {
    if (bccContainer) {
      bccContainer.remove()
      bccContainer = null
    }
    // Clear value when email type is deselected
    window.__kcBccValue = ''
  })
}

export default kcBccField
