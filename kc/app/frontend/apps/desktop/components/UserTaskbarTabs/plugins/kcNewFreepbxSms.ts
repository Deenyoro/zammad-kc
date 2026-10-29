// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// KC: Taskbar tab of a new SMS (FreePBX) draft.

import { buildKcDraftTabPlugin } from '#desktop/entities/kc-conversation-draft/buildKcDraftTabPlugin.ts'
import { kcFreepbxSmsDraft } from '#desktop/entities/kc-conversation-draft/drafts.ts'

import KcConversationDraft from '../Kc/KcConversationDraft.vue'

export default buildKcDraftTabPlugin(kcFreepbxSmsDraft, KcConversationDraft)
