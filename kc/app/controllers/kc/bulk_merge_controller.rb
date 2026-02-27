# KC: Bulk merge controller — merges multiple child tickets into a parent.
#
# Endpoint: POST /api/v1/kc/bulk_merge
# Params:   { ticket_ids: [1,2,3], parent_ticket_id: 99 }
#
# For each child ticket, calls merge_to() which (via Kc::MergeToClosedState)
# moves articles, creates links, sets state to "closed", and adds a KC note.
#
# Safety:
#   - Agent permission + update access on every ticket
#   - Setting guard (kc_bulk_merge must be enabled)
#   - Wrapped in transaction for atomicity
#   - Self-merge and merged-parent checks handled by Zammad's merge_to()
class Kc::BulkMergeController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  MAX_TICKETS_PER_MERGE = 50

  # POST /api/v1/kc/bulk_merge
  def create
    unless Setting.get('kc_bulk_merge')
      render json: { error: __('Bulk merge is disabled.') }, status: :unprocessable_entity
      return
    end

    ticket_ids      = params[:ticket_ids]
    parent_ticket_id = params[:parent_ticket_id]

    if !ticket_ids.is_a?(Array) || ticket_ids.blank?
      render json: { error: __('ticket_ids must be a non-empty array.') }, status: :unprocessable_entity
      return
    end

    if parent_ticket_id.blank?
      render json: { error: __('parent_ticket_id is required.') }, status: :unprocessable_entity
      return
    end

    if ticket_ids.size > MAX_TICKETS_PER_MERGE
      render json: { error: __('Too many tickets (max %s).') % MAX_TICKETS_PER_MERGE.to_s }, status: :unprocessable_entity
      return
    end

    parent_ticket = Ticket.find_by(id: parent_ticket_id)
    if parent_ticket.nil?
      render json: { error: __('Parent ticket not found.') }, status: :not_found
      return
    end

    # Verify agent has update access to parent (uses Pundit policy)
    authorize!(parent_ticket, :agent_update_access?)

    # Remove parent from child list if accidentally included
    ticket_ids = ticket_ids.map(&:to_i).uniq - [parent_ticket.id]

    if ticket_ids.empty?
      render json: { error: __('No child tickets to merge (parent was the only ticket selected).') }, status: :unprocessable_entity
      return
    end

    merged_count = 0

    ActiveRecord::Base.transaction do
      ticket_ids.each do |child_id|
        child = Ticket.find_by(id: child_id)
        if child.nil?
          raise Exceptions::UnprocessableEntity, __('Ticket #%s not found.') % child_id.to_s
        end

        # Verify agent has update access to each child (uses Pundit policy)
        authorize!(child, :agent_update_access?)

        # Merge via standard Zammad + Kc::MergeToClosedState concern
        # (moves articles, creates links, overrides state to "closed", adds KC note)
        child.merge_to(
          ticket_id: parent_ticket.id,
          user_id:   current_user.id,
        )

        merged_count += 1
      end
    end

    render json: {
      success:          true,
      parent_ticket_id: parent_ticket.id,
      merged_count:     merged_count,
    }
  rescue Pundit::NotAuthorizedError => e
    render json: { error: __('Not authorized to access ticket #%s.') % e.record.try(:number).to_s }, status: :forbidden
  rescue Exceptions::Forbidden => e
    render json: { error: e.message }, status: :forbidden
  rescue Exceptions::UnprocessableEntity => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def authenticate_and_authorize!
    authentication_check
    return if current_user&.permissions?('ticket.agent')

    raise Exceptions::Forbidden, __('Not authorized (agent permission required)')
  end
end
