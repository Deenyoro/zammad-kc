# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Service::Ticket::Bulk::UpdateInline < Service::Base
  attr_reader :user, :ticket_ids, :perform

  def initialize(user:, ticket_ids:, perform:)
    @user       = user
    @ticket_ids = ticket_ids
    @perform    = perform
    @errors     = []

    super()
  end

  def execute
    tickets.each do |ticket|
      Service::Ticket::Bulk::SingleItemUpdate
        .new(user:, ticket:, perform:)
        .execute
    rescue Service::Ticket::Bulk::SingleItemUpdate::BulkSingleError => e
      @errors << e
    end

    { async: false, total:, failed_count:, inaccessible_tickets:, invalid_tickets: }
  end

  private

  def total
    tickets.size
  end

  def failed_count
    @errors.size
  end

  def inaccessible_tickets
    @errors
      .select { |error| error.original_error.is_a? Pundit::NotAuthorizedError }
      .map(&:record)
  end

  def invalid_tickets
    @errors
      .reject { |error| error.original_error.is_a?(Pundit::NotAuthorizedError) }
      .map(&:record)
  end

  def errors
    return nil if @errors.empty?

    @errors
  end

  def success
    errors.blank?
  end

  def tickets
    @tickets ||= ::Ticket.where(id: ticket_ids)
  end
end
