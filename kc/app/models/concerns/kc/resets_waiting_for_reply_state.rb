# KC: Concern prepended into Ticket::Article to auto-transition tickets
# from "waiting for reply" to the default follow-up state ("open") when
# a non-agent creates an article.
#
# This covers the gap where articles are created via REST/GraphQL API
# or KC integrations (Teams Chat, RingCentral SMS) — paths where the
# postmaster pipeline does not run.
#
# The postmaster and existing Zammad form updaters already handle email
# inbound and web-frontend customer replies, so this concern only fires
# for the remaining article creation paths.
#
# IMPORTANT: This module is *prepended* (not included) by kc_loader.rb,
# so we must use the `prepended` hook to register callbacks.
#
# Safety:
#   - Defensive nil checks throughout
#   - Wrapped in rescue to avoid breaking article creation on errors
module Kc
  module ResetsWaitingForReplyState
    extend ActiveSupport::Concern

    prepended do
      after_create :kc_reset_waiting_for_reply_state
    rescue => e
      Rails.logger.warn "KC: ResetsWaitingForReplyState prepended block failed: #{e.message}"
    end

    private

    def kc_reset_waiting_for_reply_state
      return if Setting.get('import_mode')

      # Postmaster already handles state transitions for inbound email
      return if ApplicationHandleInfo.respond_to?(:postmaster?) && ApplicationHandleInfo.postmaster?

      # Internal notes should not affect customer-facing state
      return if internal

      # Agent articles should not reset — the agent set WFR intentionally
      sender = Ticket::Article::Sender.lookup(id: sender_id)
      return if sender.nil? || sender.name == 'Agent'

      # Only communication articles (not notes, etc.) indicate a reply
      article_type = Ticket::Article::Type.lookup(id: type_id)
      return if article_type.nil? || !article_type.communication

      ticket = Ticket.find_by(id: ticket_id)
      return if ticket.nil?

      # Only act when ticket is in "waiting for reply" state
      wfr_state = Ticket::State.find_by(name: 'waiting for reply')
      return if wfr_state.nil? || ticket.state_id != wfr_state.id

      # Transition to the default follow-up state (typically "open")
      follow_up_state = Ticket::State.find_by(default_follow_up: true)
      return if follow_up_state.nil?

      ticket.state_id = follow_up_state.id
      ticket.save!

      Rails.logger.info "KC: Ticket##{ticket.id} transitioned from 'waiting for reply' to '#{follow_up_state.name}' (article ##{id} by #{sender.name})"
    rescue => e
      Rails.logger.error "KC: Failed to reset waiting-for-reply state for article #{id}: #{e.message}"
    end
  end
end
