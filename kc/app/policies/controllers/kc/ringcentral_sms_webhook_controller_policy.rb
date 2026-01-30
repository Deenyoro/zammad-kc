# KC: Policy for RingCentral SMS webhook endpoint.
# Public access — no authentication required.
# Security is handled via subscription validation in the controller.
class Controllers::Kc::RingcentralSmsWebhookControllerPolicy < Controllers::ApplicationControllerPolicy
  default_permit!('*')
end
