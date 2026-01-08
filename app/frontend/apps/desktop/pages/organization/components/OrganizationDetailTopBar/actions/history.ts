// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import type { DetailViewActionPlugin } from '#desktop/types/actions.ts'

export default <DetailViewActionPlugin>{
  key: 'history-organization',
  label: __('History'),
  icon: 'clock-history',
  order: 200,
  permission: 'ticket.agent',
  //initialize: useOrganizationHistory,
  //onClick: (organization: Organization) => openOrganizationHistoryFlyout(organization.id),
}
