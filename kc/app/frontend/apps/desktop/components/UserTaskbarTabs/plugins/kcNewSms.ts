// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// KC: Taskbar tab of a new SMS (RingCentral) draft.

import { buildKcDraftTabPlugin } from '#desktop/entities/kc-conversation-draft/buildKcDraftTabPlugin.ts'
import { kcSmsDraft } from '#desktop/entities/kc-conversation-draft/drafts.ts'

import KcConversationDraft from '../Kc/KcConversationDraft.vue'

export default buildKcDraftTabPlugin(kcSmsDraft, KcConversationDraft)
