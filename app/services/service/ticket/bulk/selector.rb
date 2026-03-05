# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Service::Ticket::Bulk::Selector < Service::Base
  MAX_TICKET_IDS = 2_000

  attr_reader :user, :selector

  def initialize(user:, selector:)
    @user     = user
    @selector = selector

    super()
  end

  def execute
    if !selector[:ticket_ids].nil? # Allow empty array for ticket_ids
      selector[:ticket_ids].take(MAX_TICKET_IDS)
    elsif selector[:overview].present?
      overview_ticket_ids(selector[:overview])
    elsif selector[:search_query].present?
      search_ticket_ids(selector[:search_query])
    else
      raise ArgumentError, 'Invalid selector: one of ticket_ids, overview, or search_query must be provided.' # rubocop:disable Zammad/DetectTranslatableString
    end
  end

  private

  def overview_ticket_ids(overview)
    tickets = Ticket::Overviews.tickets_for_overview(overview, user)

    return [] if !tickets

    tickets
      .limit(MAX_TICKET_IDS)
      .pluck(:id)
  end

  def search_ticket_ids(query)
    Service::Search
      .new(
        current_user: user,
        query:,
        objects:      [Ticket],
        options:      { only_ids: true, limit: MAX_TICKET_IDS }
      )
      .execute
      .result[Ticket]
  end
end
