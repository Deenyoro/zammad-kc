# KC: Offer closed tickets in the "Recent Customer Tickets" list of the
# legacy desktop UI (merge dialog, link dialog, KB answer link dialog).
#
# Upstream TicketsController#ticket_related lists only the customer's open
# tickets (its fallback to all tickets never runs: the relation is always
# truthy), so a closed ticket could not be picked there as merge target.
#
# Upstream's action is left untouched — authorization, the recently viewed
# list and the asset collection all still run. Only the customer list in
# the JSON it renders is replaced by Kc::RecentCustomerTickets (open first,
# then closed, merge shells excluded), and those tickets' assets are added.
#
# Prepend target: TicketsController
module Kc
  module TicketRelatedWithClosed
    KC_TICKET_RELATED_LIMIT = 10

    def ticket_related
      @kc_ticket_related = true
      super
    ensure
      @kc_ticket_related = false
    end

    def render(*args, &)
      kc_add_closed_related_tickets(args.last[:json]) if @kc_ticket_related && args.last.is_a?(Hash)
      super
    end

    private

    def kc_add_closed_related_tickets(payload)
      return if !payload.is_a?(Hash) || !payload.key?(:ticket_ids_by_customer)

      ticket = Ticket.find_by(id: params[:ticket_id])
      return if ticket.nil?

      tickets = Kc::RecentCustomerTickets.call(
        user:             current_user,
        customer_id:      ticket.customer_id,
        except_ticket_id: ticket.id,
        limit:            KC_TICKET_RELATED_LIMIT,
      )

      assets = payload[:assets]
      tickets.each { |related| assets = related.assets(assets) }

      payload[:assets]                 = assets
      payload[:ticket_ids_by_customer] = tickets.map(&:id)
    rescue ActiveRecord::StatementInvalid
      raise
    rescue => e
      Rails.logger.error "KC: TicketRelatedWithClosed failed, using upstream list: #{e.message}"
    end
  end
end
