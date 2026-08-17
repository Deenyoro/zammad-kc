# KC: Override merged ticket state from "merged" to "closed".
#
# Standard Zammad merge sets the child ticket to state "merged", which hides
# it from most overviews. This concern wraps Ticket#merge_to to:
#   1. Reject targets that are themselves merged-away shells (upstream only
#      guards against state "merged", which KC children never have)
#   2. Call the standard merge (moves articles, creates links, sets "merged")
#   3. Override the state to "closed" so the ticket remains visible
#   4. Add a KC note explaining the merge
#
# This applies to ALL merge paths — single-ticket merge from the detail view,
# the REST ticket_merge endpoint, the GraphQL mutation, and KC bulk merge.
#
# The FollowUpClosedParent concern handles email follow-up rerouting for
# these closed-but-merged tickets.
#
# Safety:
#   - Calls super for the merge itself, so all upstream merge logic is
#     preserved and upstream exceptions (self-merge, missing target)
#     propagate normally
#   - Only KC-specific logic (state override, note) is wrapped in rescue —
#     except DB-level failures (StatementInvalid), which re-raise: after one
#     of those the surrounding transaction is aborted and swallowing it
#     would poison every later statement in a bulk merge
module Kc
  module MergeToClosedState
    extend ActiveSupport::Concern

    # True when a ticket was already merged away: KC rewrites merged
    # children to "closed", so upstream's state check can no longer
    # identify them — the 'merged_into' history entry can.
    def kc_merged_shell?
      history_object = History::Object.lookup(name: 'Ticket')
      history_type   = History::Type.lookup(name: 'merged_into')
      return false if history_object.nil? || history_type.nil?

      History.exists?(
        history_object_id: history_object.id,
        history_type_id:   history_type.id,
        o_id:              id,
      )
    end

    def merge_to(data)
      # Upstream rejects targets in state "merged". KC children are
      # "closed" instead, so without this check an agent could merge a
      # ticket INTO an already-merged shell — its articles would land on a
      # ticket nobody watches while follow-ups reroute one hop short of the
      # real conversation.
      target_ticket = Ticket.find_by(id: data[:ticket_id])
      if target_ticket&.kc_merged_shell?
        raise Exceptions::UnprocessableContent, __('It is not possible to merge into an already merged ticket.')
      end

      # Let upstream merge run — if it raises (self-merge, missing target,
      # etc.) the exception propagates normally without being swallowed.
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
          note_type    = Ticket::Article::Type.lookup(name: 'note')
          agent_sender = Ticket::Article::Sender.lookup(name: 'Agent')
          if note_type.nil? || agent_sender.nil?
            Rails.logger.warn 'KC: MergeToClosedState — article type/sender lookup failed, skipping note'
            return result
          end

          # Single-merge path (Service::Ticket::Merge) passes :created_by_id,
          # KC bulk merge passes :user_id — accept both before falling back.
          acting_user_id = data[:user_id] || data[:created_by_id] || UserInfo.current_user_id || 1

          Ticket::Article.create!(
            ticket_id:     id,
            type_id:       note_type.id,
            sender_id:     agent_sender.id,
            body:          "This ticket has been closed and merged into ticket ##{parent_ticket.number}. All correspondence has been moved to the parent ticket.",
            internal:      false,
            created_by_id: acting_user_id,
            updated_by_id: acting_user_id,
          )
        end
      rescue ActiveRecord::StatementInvalid
        # DB-level failure: the enclosing transaction (bulk merge) is now
        # aborted — every further statement would fail. Must propagate so
        # the whole bulk rolls back cleanly instead of 500ing later.
        raise
      rescue => e
        Rails.logger.error "KC: MergeToClosedState post-merge error: #{e.message}"
      end

      result
    end
  end
end
