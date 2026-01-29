# KC: Policy for Teams Chat webhook endpoint.
# Public access — no authentication required.
# Security is handled via clientState validation in the controller.
class Controllers::Kc::TeamsChatWebhookControllerPolicy < Controllers::ApplicationControllerPolicy
  default_permit!('*')
end
