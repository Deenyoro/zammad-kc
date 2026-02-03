# KC: Fix for Zammad bug in Ticket::Article::AddsMetadataGeneral
#
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
# Fix: Compare origin_by_id to created_by_id (Integer vs Integer)
#
# Safe for upstream upgrades:
#   - If Zammad fixes this, our override does the same correct logic (no-op)
#   - If Zammad removes/renames the method, kc_loader.rb logs a warning
#
module Kc::FixOriginBySenderOverride
  extend ActiveSupport::Concern

  private

  # Override the buggy upstream method with corrected ID comparison
  def metadata_general_process_origin_by
    return if origin_by_id.blank?

    # In case the customer is using origin_by_id, force it to current session user
    # and set sender to Customer
    if !created_by.permissions?('ticket.agent')
      self.origin_by_id = created_by_id
      self.sender = Ticket::Article::Sender.lookup(name: 'Customer')
    end

    # In case origin_by is different than created_by, set sender to Customer
    # Customer in context of this conversation, not as a permission
    #
    # FIX: Compare origin_by_id (Integer) to created_by_id (Integer)
    # Upstream bug compared origin_by (User) to created_by_id (Integer)
    return if origin_by_id == created_by_id

    self.sender = Ticket::Article::Sender.lookup(name: 'Customer')
  end
end
