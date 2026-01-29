# KC Overlay — bootstraps custom extensions into the Zammad runtime.
#
# This initializer:
#   1. Defines the top-level Kc module
#   2. Registers lib/kc/ on the autoload path
#   3. Uses Rails `to_prepare` to prepend KC concerns into upstream models
#
# It runs after all upstream initializers because the filename sorts last
# alphabetically within config/initializers/.

module Kc; end

# Make lib/kc/ autoloadable so classes like Kc::MyService resolve automatically.
Rails.application.config.autoload_paths    << Rails.root.join('lib/kc')
Rails.application.config.eager_load_paths  << Rails.root.join('lib/kc')

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
