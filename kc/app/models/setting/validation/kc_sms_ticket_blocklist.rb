# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Setting::Validation::KcSmsTicketBlocklist < Setting::Validation::Base
  def run
    Kc::SmsTicketBlocklist.validate!(value)
    result_success
  rescue ArgumentError => e
    result_failed(e.message)
  end
end
