# KC: Concern prepended into Ticket to prevent locked tickets from being
# reopened by customer activity.
#
# Intercepts ALL state changes at the model level via before_save, which
# covers every entry point: email postmaster, SMS inbound, form updaters,
# REST/GraphQL API, bulk updates, and KC integrations.
#
# Rules:
#   1. Only fires when state_id actually changed
#   2. Only fires when the ORIGINAL state (before change) is a locked state
#   3. ALLOW if transitioning to the locked state's next_state_id (scheduler)
#   4. ALLOW if no user session (system context: triggers, macros, schedulers)
#   5. ALLOW if current user has ticket.agent or admin permission
#   6. BLOCK otherwise — revert state_id, log the blocked attempt
#
# The article is still created and visible to agents; only the state
# change is prevented.
#
# IMPORTANT: This module is *prepended* (not included) by kc_loader.rb,
# so we must use the `prepended` hook to register callbacks.
module Kc
  module PreventsLockedTicketReopen
    extend ActiveSupport::Concern

    LOCKED_STATE_NAMES = ['closed (locked)', 'closed (locked until)'].freeze

    prepended do
      before_save :kc_prevent_locked_ticket_reopen
    rescue => e
      Rails.logger.warn "KC: PreventsLockedTicketReopen prepended block failed: #{e.message}"
    end

    private

    def kc_prevent_locked_ticket_reopen
      return if Setting.get('import_mode')

      # Only act when state_id is actually changing
      state_change = changes_to_save['state_id']
      return if state_change.blank?

      original_state_id = state_change[0]
      new_state_id      = state_change[1]

      # On create there is no original state
      return if original_state_id.nil?

      # Only act when the original state is a locked state
      locked_states = kc_locked_states_map
      return if locked_states.empty?

      locked_state = locked_states[original_state_id]
      return if locked_state.nil?

      # ALLOW: scheduler transitioning to the configured next_state
      return if locked_state.next_state_id.present? && new_state_id == locked_state.next_state_id

      # ALLOW: system context (triggers, macros, schedulers) where no
      # user session is active.  TransactionDispatcher explicitly sets
      # UserInfo.current_user_id = nil before running backends.
      return if UserInfo.current_user_id.nil?

      # ALLOW: agents/admins can always change the state of locked tickets
      return if kc_current_user_is_agent?

      # BLOCK: revert the state change
      Rails.logger.info "KC: Blocked state change on Ticket##{id} from '#{locked_state.name}' " \
                        "to state_id=#{new_state_id} (user_id=#{UserInfo.current_user_id || 'nil'})"
      self.state_id = original_state_id
    rescue => e
      Rails.logger.error "KC: PreventsLockedTicketReopen failed for Ticket##{id}: #{e.message}"
    end

    # Returns a hash of { state_id => Ticket::State } for the locked states.
    # Cached with a short TTL so state additions/renames are picked up
    # without a restart, while avoiding per-save DB queries on every ticket.
    def kc_locked_states_map
      Rails.cache.fetch('kc_locked_states_map', expires_in: 60.seconds) do
        Ticket::State.where(name: LOCKED_STATE_NAMES).index_by(&:id)
      end
    rescue => e
      Rails.logger.error "KC: Failed to load locked states: #{e.message}"
      {}
    end

    def kc_current_user_is_agent?
      user_id = UserInfo.current_user_id
      return false if user_id.nil?

      user = User.find_by(id: user_id)
      return false if user.nil?

      user.permissions?('ticket.agent') || user.permissions?('admin')
    rescue => e
      Rails.logger.error "KC: Failed to check agent permission: #{e.message}"
      false
    end
  end
end
