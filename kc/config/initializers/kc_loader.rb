# KC Overlay — bootstraps custom extensions into the Zammad runtime.
#
# This initializer:
#   1. Defines the top-level Kc module
#   2. Uses Rails `to_prepare` to prepend KC concerns into upstream models
#
# Autoloading: lib/kc/ is already autoloaded by Zammad's config.autoload_lib
# in config/application.rb. Files under app/ (models, controllers, services,
# concerns) are autoloaded by Rails conventions. No manual path registration
# is needed.

module Kc; end

Rails.application.config.to_prepare do
  Rails.logger.info 'KC: Loading custom overlay extensions...'

  # ---------------------------------------------------------------------------
  # Register concern prepends here.
  #
  # Each line prepends a KC concern module into an upstream Zammad model.
  # The concern files live in app/models/concerns/kc/ and are autoloaded by
  # Rails, so you only need to add the prepend line here.
  #
  # Examples:
  #   User.prepend    Kc::UserExtension
  #   Ticket.prepend  Kc::TicketExtension
  #   Group.prepend   Kc::GroupExtension
  # ---------------------------------------------------------------------------

  Rails.logger.info 'KC: Overlay loading complete.'
end
