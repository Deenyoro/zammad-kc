# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class OnlineNotificationStandalone < ApplicationModel
  validates :kind, inclusion: { in: %w[bulk_job] }
end
