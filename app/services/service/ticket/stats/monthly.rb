# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class Service::Ticket::Stats::Monthly < Service::BaseWithCurrentUser
  def execute(conditions:)
    now = Time.zone.now
    base_scope = TicketPolicy::ReadScope.new(current_user).resolve

    (0..11).map do |steps_back|
      date_to_check = now - steps_back.month
      date_start = "#{date_to_check.year}-#{date_to_check.month}-01 00:00:00"
      date_end   = "#{date_to_check.year}-#{date_to_check.month}-#{date_to_check.end_of_month.day} 00:00:00"

      {
        year:            date_to_check.year,
        month_number:    date_to_check.month,
        month_label:     Date::ABBR_MONTHNAMES[date_to_check.month],
        tickets_created: base_scope.where(created_at: (date_start..date_end), **conditions).count,
        tickets_closed:  base_scope.where(close_at: (date_start..date_end), **conditions).count,
      }
    end
  end
end
