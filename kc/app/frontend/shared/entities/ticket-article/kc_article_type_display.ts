// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

// KC: Display data (label + icon) for the KC article types in places that
// have no article type plugin registry, i.e. the mobile article metadata
// dialog (patched in kc/patches/ArticleMetadataDialog-kc-types.patch).
//
// Labels match the desktop article type plugins
// (apps/desktop/pages/ticket/components/TicketDetailView/article-type/plugins/kc_*.ts)
// and the legacy UI (kc_article_type_display.coffee).

export interface KcArticleTypeDisplay {
  label: string
  icon: string
}

const KC_ARTICLE_TYPES: Record<string, KcArticleTypeDisplay> = {
  teams_chat_message: { label: __('Teams Chat'), icon: 'chat' },
  ringcentral_sms_message: { label: __('RingCentral SMS'), icon: 'message' },
  freepbx_sms_message: { label: __('FreePBX SMS'), icon: 'message' },
}

export const kcArticleTypeDisplay = (
  articleType?: string | null,
): KcArticleTypeDisplay | undefined =>
  articleType ? KC_ARTICLE_TYPES[articleType] : undefined
