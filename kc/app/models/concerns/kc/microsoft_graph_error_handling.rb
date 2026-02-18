# KC: Defense-in-depth fixes for MicrosoftGraph error handling
#
# PROBLEM 1 — parse_error can return a String:
# MicrosoftGraph#parse_error does `JSON.parse(response.body)['error']` which
# returns whatever type the 'error' key holds. For standard Graph API errors
# this is a Hash, but during transient Azure failures or from the OAuth token
# endpoint, it can be a String (e.g. {"error": "invalid_grant"}).
#
# FIX: Ensure parse_error always returns a Hash by wrapping non-Hash values.
#
# PROBLEM 2 — raw error response is never logged:
# When handle_error! is called, the raw HTTP response body is not logged.
# If error parsing loses information (or crashes, as in the ApiError bug),
# the actual error message from Microsoft is lost forever.
#
# FIX: Log the raw HTTP status and response body before parsing.
#
# These fixes are defense-in-depth complements to
# Kc::MicrosoftGraphApiErrorTypeSafety (which fixes the crash site itself).
# Together they ensure:
#   1. parse_error always returns a Hash (prevents future type confusion)
#   2. Raw error responses are logged for forensics
#   3. The real MicrosoftGraph::ApiError is always raised (not NoMethodError)
#   4. The Graph-specific retry logic in TicketArticleCommunicateEmailJob fires
#
# HARDENING:
# 1. Both methods call `super` to preserve upstream behavior
# 2. parse_error only wraps the result if it's not already a Hash
# 3. If upstream fixes these issues, the concern is harmless (Hash passes through)
# 4. If upstream removes these methods, kc_loader logs a warning and app boots

module Kc::MicrosoftGraphErrorHandling
  extend ActiveSupport::Concern

  private

  def handle_error!(response)
    body_preview = response.body.to_s.truncate(2000)
    Rails.logger.error "KC: Microsoft Graph API error — HTTP #{response.code}: #{body_preview}"
    super
  end

  def parse_error(response)
    result = super

    return result if result.is_a?(Hash)

    {
      code:    response&.code.to_s,
      message: result.to_s,
    }
  end
end
