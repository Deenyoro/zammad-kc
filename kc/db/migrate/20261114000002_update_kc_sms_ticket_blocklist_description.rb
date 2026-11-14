# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# 0.0.15: the setting text explains group-chat entries (numbers joined with &).
class UpdateKcSmsTicketBlocklistDescription < ActiveRecord::Migration[7.0]
  def up
    Kc::SmsTicketBlocklist.ensure_access!
  end

  def down; end
end
