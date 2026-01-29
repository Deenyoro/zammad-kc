# KC: Policy for TimeManagementController.
# Sidebar actions require ticket agent access; reporting requires admin.
#
# Hardening: agent_access? rescues errors so that upstream TicketPolicy API
# changes deny access (fail-closed) rather than crashing.
class Controllers::Kc::TimeManagementControllerPolicy < Controllers::ApplicationControllerPolicy
  default_permit!('admin')

  def ticket_entries?
    agent_access?
  end

  def create_entry?
    agent_access?
  end

  def destroy_entry?
    agent_access?
  end

  private

  def agent_access?
    return true if user.permissions?('admin')
    return false if record.params[:ticket_id].blank?

    ticket = Ticket.find(record.params[:ticket_id])
    TicketPolicy.new(user, ticket).agent_update_access?
  rescue => e
    Rails.logger.error "KC: TimeManagementControllerPolicy#agent_access? failed (denying): #{e.message}"
    false
  end
end
