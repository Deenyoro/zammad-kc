# KC: Policy for NewConversationsController.
# All actions require ticket.agent permission.
class Controllers::Kc::NewConversationsControllerPolicy < Controllers::ApplicationControllerPolicy
  default_permit!('ticket.agent')
end
