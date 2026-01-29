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
#
# Hardening: Each prepend is wrapped in a safety check so that upstream
# renames / removals of a target class log a warning instead of crashing the
# whole application.  This lets the app boot even if an upstream upgrade
# removes or renames a class we depend on — operators can fix the overlay at
# their own pace.

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
  # Use kc_prepend(TargetClass, Kc::ConcernModule) for safe prepending.
  #
  # Examples:
  #   kc_prepend(User,   Kc::UserExtension)
  #   kc_prepend(Ticket, Kc::TicketExtension)
  #   kc_prepend(Group,  Kc::GroupExtension)
  # ---------------------------------------------------------------------------

  # Safe prepend helper — logs a warning instead of crashing if either the
  # target class or the concern module is missing after an upstream upgrade.
  kc_prepend = lambda do |target_class_name, concern_module_name|
    target  = target_class_name.safe_constantize  if target_class_name.is_a?(String)
    target  = target_class_name                   unless target_class_name.is_a?(String)
    concern = concern_module_name.safe_constantize if concern_module_name.is_a?(String)
    concern = concern_module_name                  unless concern_module_name.is_a?(String)

    if target.nil?
      Rails.logger.warn "KC: SKIP prepend — target class '#{target_class_name}' not found (upstream removed or renamed?)"
      return
    end
    if concern.nil?
      Rails.logger.warn "KC: SKIP prepend — concern '#{concern_module_name}' not found"
      return
    end

    target.prepend(concern)
    Rails.logger.info "KC: Prepended #{concern} into #{target}"
  rescue => e
    Rails.logger.error "KC: Failed to prepend #{concern_module_name} into #{target_class_name}: #{e.message}"
  end

  kc_prepend.call('Ticket::TimeAccounting', 'Kc::TimeAccountingAgent')

  Rails.logger.info 'KC: Overlay loading complete.'
end
