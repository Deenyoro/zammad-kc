# KC: Policy for scheduled articles controller.
# Requires ticket.agent permission for all actions.
class Controllers::Kc::ScheduledArticlesControllerPolicy < Controllers::ApplicationControllerPolicy
  default_permit!('ticket.agent')
end
