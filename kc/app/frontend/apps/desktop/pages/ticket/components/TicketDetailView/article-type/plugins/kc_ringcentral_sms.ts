// KC: Article type display plugin for RingCentral SMS messages
// in the Vue 3 desktop-view timeline.
//
// Defines how ringcentral_sms_message articles are rendered: icon, label,
// and metadata. Without this plugin, RingCentral SMS articles would use
// generic fallback styling.

import type { ChannelModule } from '#desktop/pages/ticket/components/TicketDetailView/article-type/types.ts'

export default <ChannelModule>{
  name: 'ringcentral_sms_message',
  label: __('RingCentral SMS'),
  metaLabel: __('RingCentral SMS'),
  icon: 'sms',
}
