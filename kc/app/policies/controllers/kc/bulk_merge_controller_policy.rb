# KC: Policy for bulk merge controller.
# Requires ticket.agent permission for all actions.
class Controllers::Kc::BulkMergeControllerPolicy < Controllers::ApplicationControllerPolicy
  default_permit!('ticket.agent')
end
