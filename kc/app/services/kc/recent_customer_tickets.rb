# KC: "Recent customer tickets" offered as merge (and link) targets.
#
# Upstream lists only the customer's OPEN tickets there (and falls back to
# the rest only when the customer has no open ticket at all), so a closed
# ticket can never be picked from the list in the merge dialog — the most
# common KC case being a new SMS/email that belongs to an earlier, already
# closed conversation.
#
# This keeps upstream's priority (open tickets first, newest first) and fills
# the remaining slots with the customer's other tickets (closed, pending, ...),
# newest first. Excluded are:
#   - the ticket the dialog was opened for
#   - tickets in a "merged" state (as upstream)
#   - KC merge shells: children Kc::MergeToClosedState set to "closed"
#     instead of "merged". Merging into them is refused, and their
#     conversation lives on the parent anyway.
#
# Used by Kc::RecentCustomerTicketsWithClosed (GraphQL, new desktop UI) and
# Kc::TicketRelatedWithClosed (REST ticket_related, legacy UI).
class Kc::RecentCustomerTickets
  def self.call(...)
    new(...).call
  end

  def initialize(user:, customer_id:, except_ticket_id: nil, limit: 6)
    @user             = user
    @customer_id      = customer_id
    @except_ticket_id = except_ticket_id
    @limit            = limit.to_i.positive? ? limit.to_i : 6
  end

  def call
    open_tickets = base_scope
      .where(state_id: ::Ticket::State.by_category(:open).select(:id))
      .limit(@limit)
      .to_a

    remaining = @limit - open_tickets.size
    return open_tickets if remaining <= 0

    other_tickets = base_scope
      .where.not(state_id: ::Ticket::State.by_category_ids(:merged))
      .where.not(id: open_tickets.map(&:id))
    other_tickets = other_tickets.where.not(id: merged_shell_ids) if merged_shell_ids

    open_tickets + other_tickets.limit(remaining).to_a
  end

  private

  def base_scope
    scope = ::TicketPolicy::ReadScope.new(@user).resolve
      .where(customer_id: @customer_id)
      .reorder(created_at: :desc)
    return scope if @except_ticket_id.blank?

    scope.where.not(id: @except_ticket_id)
  end

  # Subquery of ticket ids carrying a 'merged_into' history entry, or nil
  # when no merge was ever recorded on this system.
  def merged_shell_ids
    return @merged_shell_ids if defined?(@merged_shell_ids)

    history_object = History::Object.lookup(name: 'Ticket')
    history_type   = History::Type.lookup(name: 'merged_into')

    @merged_shell_ids = if history_object && history_type
                          History.where(history_object_id: history_object.id, history_type_id: history_type.id).select(:o_id)
                        end
  end
end
