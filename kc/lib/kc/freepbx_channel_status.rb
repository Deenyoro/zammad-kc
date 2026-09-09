# KC: Shared connection-status bookkeeping for Freepbx::Account channels.
#
# The FreePBX admin page shows a red banner when a channel carries a
# last_connection_error, and Zammad's own channel list reads status_in /
# last_log_in. Three places need to keep that in sync — the poll job, the
# health check, and the admin page's Test button — so the read/write lives
# here instead of being copied into each of them.
module Kc
  module FreepbxChannelStatus

    private

    def store_freepbx_error(channel, message)
      channel.with_lock do
        channel.reload
        channel.options[:last_connection_error]    = message.to_s.truncate(500)
        channel.options[:last_connection_error_at] = Time.current.utc.iso8601
        channel.status_in   = 'error'
        channel.last_log_in = message.to_s.truncate(500)
        channel.save!
      end
    rescue StandardError => e
      Rails.logger.error "KC FreePBX: Failed to store connection error: #{e.message}"
    end

    def clear_freepbx_error(channel)
      return if channel.options[:last_connection_error].blank? && channel.status_in != 'error'

      channel.with_lock do
        channel.reload
        channel.options.delete(:last_connection_error)
        channel.options.delete(:last_connection_error_at)
        channel.status_in   = 'ok'
        channel.last_log_in = nil
        channel.save!
      end
    rescue StandardError => e
      Rails.logger.error "KC FreePBX: Failed to clear connection error: #{e.message}"
    end
  end
end
