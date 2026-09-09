# KC: Shared RingCentral authentication error handling for poll jobs and
# the API health check.
#
# Problem this solves: Kc::RingcentralApi.with_channel_tokens only refreshes
# the access token when it is older than ~50 minutes. If RingCentral rejects
# the token inside that window (revoked, rotated by another client, refresh
# chain broken) the API call raises, the job logs "query failed" and returns,
# and nothing is recorded on the channel — the admin page stays green and the
# scheduler status stays "ok" while the channel is dead.
#
# rc_call_with_auth_recovery runs an API call, and on a 401:
#   1. forces one token refresh and re-runs the call
#   2. if the refresh (or the retried call) fails, writes last_auth_error /
#      last_auth_error_at on the channel so the UI shows the auth banner
#
# Include this module and call the helpers; nothing here raises.
module Kc
  module RingcentralAuthRecovery

    # Yields a RingCentral client for the channel and returns
    # [result, client]. On a 401 the token is force-refreshed once and the
    # block re-run with the new client. Returns [nil, nil] when the call
    # could not be completed; the auth failure is then already recorded on
    # the channel.
    #
    # @param channel [Channel]
    # @param label   [String] log prefix, e.g. 'KC RingCentral Poll'
    # @param client  [Kc::RingcentralApi, nil] existing client to reuse
    def rc_call_with_auth_recovery(channel, label, client: nil)
      rc_class = 'Kc::RingcentralApi'.safe_constantize
      return [nil, nil] if rc_class.nil?

      client ||= rc_class.with_channel_tokens(channel)
      [yield(client), client]
    rescue rc_class::AuthError => e
      Rails.logger.warn "#{label}: RingCentral rejected the access token for channel #{channel.id} (#{e.message}) — forcing token refresh"

      begin
        client = rc_class.with_channel_tokens(channel, force_refresh: true)
      rescue StandardError => refresh_error
        rc_record_auth_failure(channel, label, refresh_error.message)
        return [nil, nil]
      end

      begin
        result = yield(client)
        clear_auth_error(channel)
        [result, client]
      rescue rc_class::AuthError => retry_error
        rc_record_auth_failure(channel, label, retry_error.message)
        [nil, nil]
      end
    end

    def rc_record_auth_failure(channel, label, message)
      store_auth_error(channel, message)
      Rails.logger.error "#{label}: RingCentral authentication failed for channel #{channel.id}: #{message} — " \
                         'Reauthenticate the channel in Admin > KC Extensions > RingCentral SMS.'
    end

    def store_auth_error(channel, message)
      channel.with_lock do
        channel.reload
        channel.options[:last_auth_error]    = message.to_s.truncate(500)
        channel.options[:last_auth_error_at] = Time.current.utc.iso8601
        channel.status_in = 'error'
        channel.last_log_in = message.to_s.truncate(500)
        channel.save!
      end
    rescue StandardError => e
      Rails.logger.error "KC RingCentral: Failed to store auth error on channel #{channel.id}: #{e.message}"
    end

    def clear_auth_error(channel)
      channel.with_lock do
        channel.reload
        changed = false
        if channel.options[:last_auth_error].present?
          channel.options.delete(:last_auth_error)
          channel.options.delete(:last_auth_error_at)
          changed = true
        end
        if channel.status_in == 'error'
          channel.status_in = 'ok'
          channel.last_log_in = nil
          changed = true
        end
        channel.save! if changed
      end
    rescue StandardError => e
      Rails.logger.error "KC RingCentral: Failed to clear auth error on channel #{channel.id}: #{e.message}"
    end
  end
end
