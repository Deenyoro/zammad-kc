# KC: Reroute follow-ups for closed tickets that were bulk-merged.
#
# Standard Zammad only reroutes follow-ups for tickets in the "merged" state.
# KC's bulk merge sets child tickets to "closed" (so they stay visible in
# overviews), which means follow-up emails would reopen the child instead of
# going to the parent.
#
# This concern extends Channel::Filter::FollowUpMerged.find_merge_follow_up_ticket
# to also check closed tickets that have a parent link (created by merge_to).
#
# Normal closed tickets (no parent link) are NOT affected — only those that
# were bulk-merged will have a parent link, so the Link.list check naturally
# filters them out.
#
# Prepend target: Channel::Filter::FollowUpMerged.singleton_class
module Kc
  module FollowUpClosedParent
    extend ActiveSupport::Concern

    def find_merge_follow_up_ticket(ticket)
      # Try standard merge rerouting first (handles "merged" state)
      result = super
      return result if result

      # KC extension: also reroute for "closed" tickets with a parent link.
      # This handles tickets that were bulk-merged (state set to closed
      # instead of merged).
      return if ticket.state.state_type.name != 'closed'

      Link
        .list(
          link_object:       'Ticket',
          link_object_value: ticket.id
        ).lazy
        .filter_map do |link|
          next if link['link_type'] != 'parent'
          next if link['link_object'] != 'Ticket'

          Ticket
            .joins(state: :state_type)
            .where.not(ticket_state_types: { name: 'merged' })
            .find_by(id: link['link_object_value'])
        end
        .first
    rescue => e
      Rails.logger.warn "KC: FollowUpClosedParent error: #{e.message}"
      nil
    end
  end
end
