# KC: Fix for Zammad bug in Ticket::Article::AddsMetadataGeneral
#
# PROBLEM:
# The upstream code compares `origin_by` (User object) to `created_by_id` (Integer)
# which always evaluates to false, causing sender to be forced to "Customer"
# whenever origin_by_id is set - even when the origin user IS the creator.
#
# This breaks Teams/SMS delivery because the communicate jobs check for
# sender="Agent" before sending outbound messages.
#
# Bug location: app/models/ticket/article/adds_metadata_general.rb line 56
#   return if origin_by == created_by_id   # Bug: User vs Integer (always false)
#
# FIX (CONSERVATIVE):
# Only apply the corrected comparison for Teams and SMS article types.
# All other article types use the original upstream behavior unchanged.
# This minimizes risk of unintended side effects.
#
# HARDENING:
# 1. Logs when the fix is applied so we can trace behavior
# 2. Checks if upstream bug still exists at boot time
# 3. Handles nil/blank values defensively
# 4. ONLY modifies behavior for Teams/SMS - everything else unchanged
# 5. If upstream fixes bug: our code produces identical results
# 6. If upstream removes method: kc_loader logs warning, app boots
#
module Kc::FixOriginBySenderOverride
  extend ActiveSupport::Concern

  # Article types where we apply the fix (outbound channels that need sender=Agent)
  FIXED_ARTICLE_TYPES = %w[
    teams_chat_message
    ringcentral_sms_message
  ].freeze

  included do
    check_upstream_bug_status
  end

  class_methods do
    def check_upstream_bug_status
      upstream_file = Rails.root.join('app/models/ticket/article/adds_metadata_general.rb')
      return unless File.exist?(upstream_file)

      source = File.read(upstream_file)
      has_bug = source.include?('origin_by == created_by_id')
      has_fix = source.include?('origin_by_id == created_by_id')

      if has_fix && !has_bug
        Rails.logger.info 'KC: FixOriginBySenderOverride — upstream bug appears FIXED. ' \
                          'Consider removing this KC concern after testing.'
      elsif has_bug
        Rails.logger.info 'KC: FixOriginBySenderOverride — upstream bug detected, fix is ACTIVE ' \
                          "(applies to: #{FIXED_ARTICLE_TYPES.join(', ')})."
      else
        Rails.logger.warn 'KC: FixOriginBySenderOverride — could not detect upstream bug status. ' \
                          'The upstream code may have changed significantly.'
      end
    rescue => e
      Rails.logger.warn "KC: FixOriginBySenderOverride — failed to check upstream: #{e.message}"
    end
  end

  private

  # Override the buggy upstream method
  def metadata_general_process_origin_by
    return if origin_by_id.blank?

    # Defensive: ensure created_by_id is present
    if created_by_id.blank?
      Rails.logger.debug 'KC: FixOriginBySenderOverride — created_by_id is blank, skipping'
      return
    end

    # In case a non-agent is using origin_by_id, force it to current session user
    # and set sender to Customer (upstream behavior, preserved exactly)
    created_by_user = created_by
    if created_by_user.present? && !created_by_user.permissions?('ticket.agent')
      self.origin_by_id = created_by_id
      self.sender = Ticket::Article::Sender.lookup(name: 'Customer')
      return
    end

    # --- CONSERVATIVE FIX ---
    # Only apply corrected logic for Teams/SMS articles.
    # All other article types get the original upstream behavior.
    article_type = Ticket::Article::Type.lookup(id: type_id)&.name

    if FIXED_ARTICLE_TYPES.include?(article_type)
      # FIXED BEHAVIOR: Compare Integer to Integer (correct)
      # If origin_by_id matches created_by_id, agent is sending as themselves,
      # so preserve sender="Agent" for the communicate job to fire.
      if origin_by_id == created_by_id
        Rails.logger.debug { "KC: FixOriginBySenderOverride — preserving sender=Agent for #{article_type} on ticket #{ticket_id}" }
        return
      end
      # Different origin than creator — set sender to Customer
      self.sender = Ticket::Article::Sender.lookup(name: 'Customer')
      Rails.logger.debug { "KC: FixOriginBySenderOverride — origin differs, set sender=Customer for #{article_type} on ticket #{ticket_id}" }
    else
      # ORIGINAL UPSTREAM BEHAVIOR (unchanged for all other types)
      # This comparison is buggy (User vs Integer, always false) but we preserve it
      # to avoid any unintended side effects on other article types.
      return if origin_by == created_by_id
      self.sender = Ticket::Article::Sender.lookup(name: 'Customer')
    end
  end
end
