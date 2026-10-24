# KC: Fix for Zammad bug in Ticket::Article::AddsMetadataEmail
#
# PROBLEM:
# Upstream builds the email "From" header (e.g. "Dean Thomas via KawaConnect
# Helpdesk Support") from `created_by`:
#
#   def metadata_email_process_from
#     email_address = ticket.group.email_address
#     self.from = Channel::EmailBuild.recipient_line(
#       email_address.sender_display_name(created_by), email_address.email)
#   end
#
# When an article is created via API token with `origin_by_id` set to a
# different user, the From header shows the API token owner's name instead
# of the intended author's name.
#
# The `author` method (defined in ticket/article.rb) returns:
#   origin_by || created_by
# This correctly resolves to the intended sender when origin_by_id is set.
#
# FIX:
# Override `metadata_email_process_from` to pass `author` instead of
# `created_by` to EmailAddress#sender_display_name. When origin_by_id is nil,
# `author` equals `created_by`, so behavior is identical for normal UI usage.
#
# History: until upstream 6f5ca10dfe (Aug 2026) the name was built in a private
# `recipient_name` method, which this concern overrode. Upstream moved the
# logic to EmailAddress#sender_display_name, so the override now targets
# `metadata_email_process_from` (fingerprinted in kc/upstream-fingerprints.txt).
#
# HARDENING:
# 1. Boot-time check detects if upstream has already fixed the bug
# 2. Falls back to super (upstream behavior) on any error
# 3. Logs when the fix changes behavior (origin_by differs from created_by)
# 4. When upstream fixes this: our code produces identical results
# 5. If upstream removes method: kc_loader logs warning, app boots
#
module Kc::EmailFromOriginByFix
  extend ActiveSupport::Concern

  prepended do
    kc_check_email_from_upstream_status
  end

  class_methods do
    def kc_check_email_from_upstream_status
      upstream_file = Rails.root.join('app/models/ticket/article/adds_metadata_email.rb')
      return unless File.exist?(upstream_file)

      source = File.read(upstream_file)

      if source.include?('sender_display_name(author)')
        Rails.logger.info 'KC: EmailFromOriginByFix — upstream appears FIXED (uses author). ' \
                          'Consider removing this KC concern after testing.'
      elsif source.include?('sender_display_name(created_by)')
        Rails.logger.info 'KC: EmailFromOriginByFix — upstream bug detected (uses created_by), fix is ACTIVE.'
      else
        Rails.logger.warn 'KC: EmailFromOriginByFix — could not detect upstream bug status. ' \
                          'The upstream code may have changed significantly.'
      end
    rescue => e
      Rails.logger.warn "KC: EmailFromOriginByFix — failed to check upstream: #{e.message}"
    end
  end

  private

  # Override upstream metadata_email_process_from to use `author` instead of
  # `created_by`. `author` returns origin_by || created_by, so when
  # origin_by_id is nil (normal UI usage), behavior is identical to upstream.
  def metadata_email_process_from
    effective_user = author

    # Guard: if author is somehow nil, fall back to upstream
    if effective_user.blank?
      Rails.logger.debug 'KC: EmailFromOriginByFix — author is blank, falling back to super'
      return super
    end

    email_address = ticket.group.email_address
    return super if !email_address.respond_to?(:sender_display_name)

    if origin_by_id.present? && origin_by_id != created_by_id
      Rails.logger.debug { "KC: EmailFromOriginByFix — using origin_by '#{effective_user.fullname}' instead of created_by '#{created_by&.fullname}' for email From on ticket #{ticket_id}" }
    end

    self.from = Channel::EmailBuild.recipient_line(email_address.sender_display_name(effective_user), email_address.email)
  rescue => e
    Rails.logger.error "KC: EmailFromOriginByFix#metadata_email_process_from failed: #{e.message} — falling back to upstream"
    super
  end
end
