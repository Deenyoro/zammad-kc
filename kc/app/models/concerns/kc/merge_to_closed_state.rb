# KC: Override merged ticket state from "merged" to "closed".
#
# Standard Zammad merge sets the child ticket to state "merged", which hides
# it from most overviews. This concern wraps Ticket#merge_to to:
#   1. Call the standard merge (moves articles, creates links, sets "merged")
#   2. Override the state to "closed" so the ticket remains visible
#   3. Add a KC note explaining the merge
#
# This applies to ALL merge paths — both single-ticket merge from the detail
# view and bulk merge from the overview.
#
# The FollowUpClosedParent concern handles email follow-up rerouting for
# these closed-but-merged tickets.
#
# Safety:
#   - Calls super first, so all upstream merge logic is preserved
#   - Upstream exceptions (self-merge, missing target) propagate normally
#   - Only KC-specific logic (state override, note) is wrapped in rescue
module Kc
  module MergeToClosedState
    extend ActiveSupport::Concern

    def merge_to(data)
      # Let upstream merge run — if it raises (self-merge, missing target, etc.)
      # the exception propagates normally without being swallowed.
      result = super

      # KC post-merge: override state and add note.
      # Wrapped in its own begin/rescue so upstream merge is never undone
      # by a failure in the KC extension.
      begin
        closed_state = Ticket::State.find_by(name: 'closed')
        if closed_state.nil?
          Rails.logger.warn 'KC: MergeToClosedState — closed state not found, skipping override'
          return result
        end

        # Override state from "merged" to "closed"
        reload
        update!(state: closed_state)

        # Add KC note explaining the merge
        parent_ticket = Ticket.find_by(id: data[:ticket_id])
        if parent_ticket
          Ticket::Article.create!(
            ticket_id:     id,
            type_id:       Ticket::Article::Type.lookup(name: 'note').id,
            sender_id:     Ticket::Article::Sender.lookup(name: 'Agent').id,
            body:          "This ticket has been closed and merged into ticket ##{parent_ticket.number}. All correspondence has been moved to the parent ticket.",
            internal:      false,
            created_by_id: data[:user_id] || UserInfo.current_user_id || 1,
            updated_by_id: data[:user_id] || UserInfo.current_user_id || 1,
          )
        end
      rescue => e
        Rails.logger.error "KC: MergeToClosedState post-merge error: #{e.message}"
      end

      result
    end
  end
end
