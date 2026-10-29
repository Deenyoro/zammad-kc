# KC: Offer closed tickets in the "Recent customer tickets" list of the new
# desktop UI (merge and link flyouts).
#
# Upstream Gql::Queries::Tickets::RecentByCustomer returns only the
# customer's open tickets whenever there is at least one, so a closed ticket
# could not be chosen there as merge target. Kc::RecentCustomerTickets keeps
# open tickets first and fills the rest of the list with the customer's
# closed tickets (merge shells excluded).
#
# Prepend target: Gql::Queries::Tickets::RecentByCustomer
#
# Safety: any Ruby-level failure in the KC list falls back to upstream's
# resolve, so the dialog never breaks because of this extension.
module Kc
  module RecentCustomerTicketsWithClosed
    def resolve(customer:, limit: 6, except_ticket_internal_id: nil)
      Kc::RecentCustomerTickets.call(
        user:             context.current_user,
        customer_id:      customer.id,
        except_ticket_id: except_ticket_internal_id,
        limit:            limit,
      )
    rescue ActiveRecord::StatementInvalid
      raise
    rescue => e
      Rails.logger.error "KC: RecentCustomerTicketsWithClosed failed, using upstream list: #{e.message}"
      super
    end
  end
end
