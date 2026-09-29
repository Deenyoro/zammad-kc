# KC: Policy for the FreePBX SMS webhook endpoint.
# Public access — the controller authenticates the connector by its token.
class Controllers::Kc::FreepbxSmsWebhookControllerPolicy < Controllers::ApplicationControllerPolicy
  default_permit!('*')
end
