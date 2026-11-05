# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class AddKcSmsTicketBlocklist < ActiveRecord::Migration[7.0]
  def up
    Kc::SmsTicketBlocklist.ensure_setting!
  end

  def down
    Setting.find_by(name: Kc::SmsTicketBlocklist::SETTING_NAME)&.destroy!
  end
end
