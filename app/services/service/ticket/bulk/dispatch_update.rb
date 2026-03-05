# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Service::Ticket::Bulk::DispatchUpdate < Service::Base
  BACKGROUND_UPDATE_THRESHOLD = ENV.fetch('ZAMMAD_UI_BULK_BACKGROUND_UPDATE_THRESHOLD', 20).to_i

  attr_reader :user, :selector, :perform

  def initialize(user:, selector:, perform:)
    @user     = user
    @selector = selector
    @perform  = perform

    super()
  end

  def execute
    background_update? ? schedule_background_update : perform_update_now
  end

  private

  def ticket_ids
    @ticket_ids ||= Service::Ticket::Bulk::Selector
      .new(user:, selector:)
      .execute
  end

  def schedule_background_update
    Gql::Subscriptions::User::Current::Ticket::BulkUpdateStatusUpdates
      .trigger(
        { status: 'pending', total: ticket_ids.size },
        scope: user.id
      )

    TicketBulkUpdateJob.perform_later(user:, ticket_ids:, perform:)

    { async: true, total: ticket_ids.size }
  end

  def perform_update_now
    Service::Ticket::Bulk::UpdateInline
      .new(user:, ticket_ids:, perform:)
      .execute
  end

  def background_update?
    ticket_ids.size >= BACKGROUND_UPDATE_THRESHOLD
  end
end
