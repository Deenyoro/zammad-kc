# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class AddKcSmsTicketBlocklistPermission < ActiveRecord::Migration[7.0]
  def up
    Kc::SmsTicketBlocklist.ensure_access!
  end

  def down
    setting = Setting.find_by(name: Kc::SmsTicketBlocklist::SETTING_NAME)
    if setting
      setting.preferences[:permission] = ['admin']
      setting.save!
    end
    Permission.find_by(name: Kc::SmsTicketBlocklist::PERMISSION_NAME)&.destroy!
  end
end
