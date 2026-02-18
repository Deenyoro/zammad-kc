# KC: Fix type-safety bug in MicrosoftGraph::ApiError#initialize
#
# PROBLEM:
# MicrosoftGraph::ApiError#initialize calls .with_indifferent_access on
# `error_hash`, assuming it is always a Hash. However, MicrosoftGraph#parse_error
# can return a String when the Microsoft Graph API returns a non-standard error
# format: {"error": "some_string"} instead of {"error": {"code": ..., "message": ...}}.
#
# This causes:
#   NoMethodError: undefined method 'with_indifferent_access' for an instance of String
#
# The crash prevents ApiError from ever being instantiated, which means:
#   1. The real Graph API error message is lost
#   2. The Graph-specific rescue_from handler in TicketArticleCommunicateEmailJob
#      never fires (it rescues MicrosoftGraph::ApiError, but gets NoMethodError instead)
#   3. Retry-After header support and intelligent backoff are bypassed
#   4. The generic retry_on catches it with aggressive 25s intervals, all 4 retries
#      fire during the API instability window, and the email permanently fails
#
# SECOND CRASH PATH (also fixed by this concern):
# Channel::Driver::BaseEmailOutbound#deliver_mail rescues errors and re-raises
# with `raise e.class, humanized_error_message(e, options)`. This calls
# ApiError.new("Microsoft Graph API: <message>") — passing a String. Without
# this fix, EVERY MicrosoftGraph::ApiError during outbound email delivery would
# crash at the re-raise, falling through to the generic retry_on handler.
#
# Root cause: Microsoft APIs can return {"error": "string"} (RFC 6749 format)
# during transient Azure failures, rate limiting, or from the OAuth token endpoint,
# instead of the documented {"error": {"code": ..., "message": ...}} (OData format).
#
# Bug location: lib/microsoft_graph/api_error.rb line 8
#   @error = error_hash.with_indifferent_access   # crashes when error_hash is a String
#
# FIX:
# Normalize error_hash to a Hash before calling super (the original initialize).
# - Hash: passed through as-is (normal path)
# - String: wrapped in {"code": "UnknownError", "message": <the string>}
# - Other: converted to string and wrapped
#
# HARDENING:
# 1. Preserves the original error string as the :message so it appears in logs
# 2. Uses "UnknownError" as code since the real code was not parseable
# 3. If upstream fixes the bug, this concern still works (Hash passes through unchanged)
# 4. If upstream removes ApiError, kc_loader logs a warning and app boots normally
# 5. Boot-time check logs whether upstream bug is still present
#
# Ref: Zammad issue not yet filed. Confirmed unfixed as of develop@b70cb79 (Feb 2026).
# Ref: Similar bugs in msgraph-sdk-dotnet#69, Dawarich#2056.

module Kc::MicrosoftGraphApiErrorTypeSafety
  extend ActiveSupport::Concern

  included do
    kc_check_upstream_api_error_bug
  end

  class_methods do
    def kc_check_upstream_api_error_bug
      source_file = Rails.root.join('lib/microsoft_graph/api_error.rb')
      return unless File.exist?(source_file)

      source = File.read(source_file)

      if source.include?('error_hash.with_indifferent_access') && !source.match?(/case\s+error_hash/)
        Rails.logger.info 'KC: MicrosoftGraphApiErrorTypeSafety — upstream bug detected (unchecked .with_indifferent_access), fix is ACTIVE.'
      else
        Rails.logger.info 'KC: MicrosoftGraphApiErrorTypeSafety — upstream may have fixed the type-safety bug. ' \
                          'Consider removing this KC concern after testing.'
      end
    rescue => e
      Rails.logger.warn "KC: MicrosoftGraphApiErrorTypeSafety — failed to check upstream: #{e.message}"
    end
  end

  def initialize(error_hash, retry_after: nil)
    normalized = case error_hash
                 when Hash
                   error_hash
                 when String
                   { 'code' => 'UnknownError', 'message' => error_hash }
                 else
                   { 'code' => 'UnknownError', 'message' => error_hash.to_s }
                 end

    super(normalized, retry_after: retry_after)
  end
end
