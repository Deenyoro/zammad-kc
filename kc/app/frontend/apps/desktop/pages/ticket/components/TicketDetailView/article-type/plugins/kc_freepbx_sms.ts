// KC: Article type display plugin for FreePBX SMS messages in the Vue 3
// desktop-view timeline: icon, label and metadata for
// freepbx_sms_message articles.

import type { ChannelModule } from '#desktop/pages/ticket/components/TicketDetailView/article-type/types.ts'

export default <ChannelModule>{
  name: 'freepbx_sms_message',
  label: __('FreePBX SMS'),
  metaLabel: __('FreePBX SMS'),
  icon: 'sms',
}
