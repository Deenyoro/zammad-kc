# KC: Policy for RingCentral SMS admin channel management.
# Requires admin permission for all actions.
class Controllers::Kc::RingcentralSmsChannelsControllerPolicy < Controllers::ApplicationControllerPolicy
  default_permit!('admin')
end
