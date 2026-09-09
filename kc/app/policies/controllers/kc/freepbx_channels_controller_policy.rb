# KC: Policy for FreePBX admin channel management.
# Requires admin permission for all actions.
class Controllers::Kc::FreepbxChannelsControllerPolicy < Controllers::ApplicationControllerPolicy
  default_permit!('admin')
end
