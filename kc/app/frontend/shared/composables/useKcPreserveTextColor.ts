// KC: Shared reactive flag for the "Send with text color" feature.
//
// When an agent clicks "Send with text color" in the Update button dropdown,
// this flag is set to true. The editTicket function in useTicketEdit.ts
// consumes this flag and passes it to processArticle, which injects
// kc_preserve_text_color into the article preferences sent to the backend.
//
// The flag is module-scoped (singleton) so it persists across the async form
// validation + submission pipeline within the same browser tab.
//
// Safety: a 30-second timeout auto-clears the flag in case form validation
// fails and the flag is never consumed by editTicket.

import { ref } from 'vue'

const preserveTextColor = ref(false)
let clearTimer: ReturnType<typeof setTimeout> | undefined

export const useKcPreserveTextColor = () => {
  const setPreserveTextColor = () => {
    preserveTextColor.value = true

    // Auto-clear after 30s to prevent stale flags if submission never fires
    // (e.g., form validation failure prevents editTicket from running).
    if (clearTimer) clearTimeout(clearTimer)
    clearTimer = setTimeout(() => {
      preserveTextColor.value = false
      clearTimer = undefined
    }, 30_000)
  }

  const consumePreserveTextColor = () => {
    const value = preserveTextColor.value
    preserveTextColor.value = false
    if (clearTimer) {
      clearTimeout(clearTimer)
      clearTimer = undefined
    }
    return value
  }

  return {
    preserveTextColor,
    setPreserveTextColor,
    consumePreserveTextColor,
  }
}
