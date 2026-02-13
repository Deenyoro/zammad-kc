// KC: Article type display plugin for Microsoft Teams Chat messages
// in the Vue 3 desktop-view timeline.
//
// Defines how teams_chat_message articles are rendered: icon, label, and
// metadata. Without this plugin, Teams Chat articles would use generic
// fallback styling.

import type { ChannelModule } from '#desktop/pages/ticket/components/TicketDetailView/article-type/types.ts'

export default <ChannelModule>{
  name: 'teams_chat_message',
  label: __('Teams Chat'),
  metaLabel: __('teams chat'),
  icon: 'chat',
}
