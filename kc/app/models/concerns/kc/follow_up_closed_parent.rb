# KC: Reroute follow-ups for closed tickets that were merged.
#
# Standard Zammad only reroutes follow-ups for tickets in the "merged" state.
# KC's merge sets child tickets to "closed" (so they stay visible in
# overviews), which means follow-up emails would reopen the child instead of
# going to the parent.
#
# This concern extends Channel::Filter::FollowUpMerged.find_merge_follow_up_ticket
# to also check closed tickets — but ONLY those with actual merge evidence.
#
# A parent link alone is NOT enough: agents create parent/child links by hand
# via the Links sidebar, and rerouting those would silently move a customer's
# reply onto an unrelated ticket (possibly another customer's). Every merge
# writes a 'merged_into' history entry on the child (Ticket#merge_to), so that
# entry is required before rerouting.
#
# Prepend target: Channel::Filter::FollowUpMerged.singleton_class
module Kc
  module FollowUpClosedParent
    extend ActiveSupport::Concern

    def find_merge_follow_up_ticket(ticket)
      # Try standard merge rerouting first (handles "merged" state).
      # Deliberately NOT inside the rescue below: if upstream's own path
      # fails transiently, the postmaster run must abort and retry the mail
      # later — swallowing it here would misroute the follow-up instead.
      result = super
      return result if result

      begin
        # KC extension: also reroute for "closed" tickets that were merged
        # (state set to closed instead of merged by Kc::MergeToClosedState).
        return if ticket.state.state_type.name != 'closed'

        # Require actual merge evidence — a 'merged_into' history entry.
        history_object = History::Object.lookup(name: 'Ticket')
        history_type   = History::Type.lookup(name: 'merged_into')
        return if history_object.nil? || history_type.nil?
        return if !History.exists?(
          history_object_id: history_object.id,
          history_type_id:   history_type.id,
          o_id:              ticket.id,
        )

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
end
