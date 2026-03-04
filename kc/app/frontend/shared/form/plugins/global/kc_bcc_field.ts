// KC: BCC field access control guard.
//
// This FormKit global plugin is auto-discovered via import.meta.glob in
// app/frontend/shared/form/index.ts.
//
// The BCC field itself is now a native FormKit schema node (recipient type,
// matching CC exactly). This plugin only controls visibility based on the
// kc_bcc_access admin setting:
//   - 'all'      → visible to all agents (default)
//   - 'admin'    → visible only to admin users
//   - 'disabled' → hidden for everyone

import type { FormKitNode } from '@formkit/core'

import { useApplicationStore } from '#shared/stores/application.ts'
import { useSessionStore } from '#shared/stores/session.ts'

const kcBccField = (node: FormKitNode) => {
  if (node.name !== 'bcc' || node.type !== 'input') return

  node.on('created', () => {
    try {
      const { config } = useApplicationStore()
      const bccAccess = (config.kc_bcc_access as string) ?? 'all'

      if (bccAccess === 'all') return

      if (bccAccess === 'disabled') {
        node.destroy()
        return
      }

      if (bccAccess === 'admin') {
        const session = useSessionStore()
        if (!session.hasPermission('admin')) {
          node.destroy()
        }
      }
    } catch {
      // Stores not available — allow BCC by default
    }
  })
}

export default kcBccField
