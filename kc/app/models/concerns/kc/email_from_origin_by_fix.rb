# KC: Fix for Zammad bug in Ticket::Article::AddsMetadataEmail
#
# PROBLEM:
# The upstream `recipient_name` method uses `created_by` to build the email
# "From" header (e.g. "Dean Thomas via KawaConnect Helpdesk Support").
# When an article is created via API token with `origin_by_id` set to a
# different user, the From header shows the API token owner's name instead
# of the intended author's name.
#
# Bug location: app/models/ticket/article/adds_metadata_email.rb lines 69-81
#   `recipient_name` uses `created_by.firstname` / `created_by.lastname`
#   instead of `author.firstname` / `author.lastname`
#
# The `author` method (defined in ticket/article.rb) returns:
#   origin_by || created_by
# This correctly resolves to the intended sender when origin_by_id is set.
#
# FIX:
# Override `recipient_name` to use `author` (origin_by || created_by)
# instead of `created_by`. When origin_by_id is nil, `author` equals
# `created_by`, so behavior is identical for normal (non-API-token) usage.
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
      uses_created_by = source.include?('created_by.firstname') && source.include?('created_by.lastname')
      uses_author     = source.include?('author.firstname') && source.include?('author.lastname')

      if uses_author && !uses_created_by
        Rails.logger.info 'KC: EmailFromOriginByFix — upstream appears FIXED (uses author). ' \
                          'Consider removing this KC concern after testing.'
      elsif uses_created_by
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

  # Override upstream recipient_name to use `author` instead of `created_by`.
  # `author` returns origin_by || created_by, so when origin_by_id is nil
  # (normal UI usage), behavior is identical to upstream.
  def recipient_name(email_address)
    # Use author (origin_by || created_by) for the display name
    effective_user = author

    # Guard: if author is somehow nil, fall back to upstream
    if effective_user.blank?
      Rails.logger.debug 'KC: EmailFromOriginByFix — author is blank, falling back to super'
      return super
    end

    if effective_user.id != 1
      case Setting.get('ticket_define_email_from')
      when 'AgentNameSystemAddressName'
        separator = Setting.get('ticket_define_email_from_separator')

        if origin_by_id.present? && origin_by_id != created_by_id
          Rails.logger.debug { "KC: EmailFromOriginByFix — using origin_by '#{effective_user.fullname}' instead of created_by '#{created_by.fullname}' for email From on ticket #{ticket_id}" }
        end

        return "#{effective_user.firstname} #{effective_user.lastname} #{separator} #{email_address.name}"
      when 'AgentName'
        if origin_by_id.present? && origin_by_id != created_by_id
          Rails.logger.debug { "KC: EmailFromOriginByFix — using origin_by '#{effective_user.fullname}' instead of created_by '#{created_by.fullname}' for email From on ticket #{ticket_id}" }
        end

        return "#{effective_user.firstname} #{effective_user.lastname}"
      end
    end

    email_address.name
  rescue => e
    Rails.logger.error "KC: EmailFromOriginByFix#recipient_name failed: #{e.message} — falling back to upstream"
    super
  end
end
