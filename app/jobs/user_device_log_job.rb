# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class UserDeviceLogJob < ApplicationJob
  # TODO: change :never to false after migration to Rails 8
  # This job has to be queued inside transaction.
  # It is performed regardless if transaction was successful or not.
  self.enqueue_after_transaction_commit = :never

  def perform(http_user_agent, remote_ip, user_id, fingerprint, type)
    UserDevice.add(
      http_user_agent,
      remote_ip,
      user_id,
      fingerprint,
      type,
    )
  end
end
