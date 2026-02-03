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
# FIX:
# Compare origin_by_id to created_by_id (Integer vs Integer)
#
# HARDENING:
# 1. Logs when the fix is applied so we can trace behavior
# 2. Checks if upstream bug still exists at boot time
# 3. Handles nil/blank values defensively
# 4. If upstream fixes the bug, our code produces identical results (safe no-op)
# 5. If upstream removes the method, kc_loader.rb logs warning, app still boots
#
module Kc::FixOriginBySenderOverride
  extend ActiveSupport::Concern

  included do
    # Check at load time if the upstream bug still exists
    # This helps us know when Zammad fixes it upstream
    check_upstream_bug_status
  end

  class_methods do
    def check_upstream_bug_status
      # Read the upstream source to detect if bug is fixed
      upstream_file = Rails.root.join('app/models/ticket/article/adds_metadata_general.rb')
      return unless File.exist?(upstream_file)

      source = File.read(upstream_file)

      # The bug is: "return if origin_by == created_by_id" (compares User to Integer)
      # The fix is: "return if origin_by_id == created_by_id" (compares Integer to Integer)
      has_bug = source.include?('origin_by == created_by_id')
      has_fix = source.include?('origin_by_id == created_by_id')

      if has_fix && !has_bug
        Rails.logger.info 'KC: FixOriginBySenderOverride — upstream bug appears FIXED. ' \
                          'Consider removing this KC concern after testing.'
      elsif has_bug
        Rails.logger.info 'KC: FixOriginBySenderOverride — upstream bug detected, fix is ACTIVE.'
      else
        Rails.logger.warn 'KC: FixOriginBySenderOverride — could not detect upstream bug status. ' \
                          'The upstream code may have changed significantly.'
      end
    rescue => e
      Rails.logger.warn "KC: FixOriginBySenderOverride — failed to check upstream: #{e.message}"
    end
  end

  private

  # Override the buggy upstream method with corrected ID comparison
  def metadata_general_process_origin_by
    return if origin_by_id.blank?

    # Defensive: ensure created_by_id is present
    if created_by_id.blank?
      Rails.logger.debug 'KC: FixOriginBySenderOverride — created_by_id is blank, skipping'
      return
    end

    # In case a non-agent is using origin_by_id, force it to current session user
    # and set sender to Customer (upstream behavior, preserved)
    created_by_user = created_by
    if created_by_user.present? && !created_by_user.permissions?('ticket.agent')
      self.origin_by_id = created_by_id
      self.sender = Ticket::Article::Sender.lookup(name: 'Customer')
      Rails.logger.debug { "KC: FixOriginBySenderOverride — non-agent creator, forced sender=Customer for article on ticket #{ticket_id}" }
      return
    end

    # FIX: Compare Integer to Integer (not User object to Integer)
    # If origin_by_id matches created_by_id, the agent is sending as themselves
    # so we preserve sender="Agent" (do NOT override to Customer)
    if origin_by_id == created_by_id
      Rails.logger.debug { "KC: FixOriginBySenderOverride — origin matches creator, preserving sender for article on ticket #{ticket_id}" }
      return
    end

    # Different origin than creator — set sender to Customer
    # (e.g., an admin creating an article "on behalf of" someone else)
    self.sender = Ticket::Article::Sender.lookup(name: 'Customer')
    Rails.logger.debug { "KC: FixOriginBySenderOverride — origin differs from creator, set sender=Customer for article on ticket #{ticket_id}" }
  end
end
