# KC: Policy for API Health Check admin configuration.
# Requires admin permission for all actions.
class Controllers::Kc::ApiHealthCheckControllerPolicy < Controllers::ApplicationControllerPolicy
  default_permit!('admin')
end
