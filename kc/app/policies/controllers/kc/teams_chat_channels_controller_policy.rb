# KC: Policy for Teams Chat admin channel management.
# Requires admin permission for all actions.
class Controllers::Kc::TeamsChatChannelsControllerPolicy < Controllers::ApplicationControllerPolicy
  default_permit!('admin')
end
