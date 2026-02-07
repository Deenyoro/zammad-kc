# KC: Token expiration and authentication failure alerting service.
#
# Creates internal Zammad tickets when OAuth tokens fail to refresh,
# allowing admins to be notified through normal ticket channels.
#
# Features:
#   - Deduplication: Only creates one ticket per channel per day
#   - Auto-close: Closes ticket when token refresh succeeds again
#   - Clear messaging: Provides actionable instructions for re-authentication
#
# Usage:
#   Kc::TokenAlertService.alert_token_failure(
#     channel: channel,
#     service: 'RingCentral',
#     error: exception.message
#   )
#
class Kc::TokenAlertService
  ALERT_GROUP_NAME = 'Users'.freeze
  DEDUP_WINDOW = 24.hours

  class << self
    # Creates or updates an alert ticket for token refresh failures.
    # Only creates one ticket per channel per day to avoid spam.
    def alert_token_failure(channel:, service:, error:)
      return unless should_alert?(channel, service)

      ticket = find_or_create_alert_ticket(channel, service, error)
      record_alert(channel, service)
      ticket
    rescue => e
      Rails.logger.error "KC TokenAlert: Failed to create alert ticket: #{e.message}"
      nil
    end

    # Closes any open alert tickets for this channel/service when auth succeeds.
    def clear_alerts(channel:, service:)
      find_alert_tickets(channel, service, state: 'open').each do |ticket|
        close_ticket(ticket, service)
      end
    rescue => e
      Rails.logger.warn "KC TokenAlert: Failed to close alert tickets: #{e.message}"
    end

    private

    def should_alert?(channel, service)
      # Check if we've already alerted for this channel/service in the last 24h
      cache_key = alert_cache_key(channel, service)
      last_alert = Rails.cache.read(cache_key)

      last_alert.nil? || last_alert < DEDUP_WINDOW.ago
    end

    def record_alert(channel, service)
      cache_key = alert_cache_key(channel, service)
      Rails.cache.write(cache_key, Time.current, expires_in: DEDUP_WINDOW)
    end

    def alert_cache_key(channel, service)
      "kc_token_alert:#{service.downcase}:#{channel.id}"
    end

    def find_or_create_alert_ticket(channel, service, error)
      # Look for existing open ticket
      existing = find_alert_tickets(channel, service, state: 'open').first

      if existing
        update_ticket(existing, service, error)
      else
        create_ticket(channel, service, error)
      end
    end

    def find_alert_tickets(channel, service, state: nil)
      query = Ticket.where(
        title: alert_ticket_title(service, channel),
      )

      if state
        state_ids = Ticket::State.where(name: state).pluck(:id)
        query = query.where(state_id: state_ids)
      end

      query.order(created_at: :desc)
    end

    def create_ticket(channel, service, error)
      group = Group.find_by(name: ALERT_GROUP_NAME) || Group.first
      return nil unless group

      Ticket.create!(
        title: alert_ticket_title(service, channel),
        group: group,
        customer_id: 1, # System user
        state: Ticket::State.find_by(name: 'new') || Ticket::State.first,
        priority: Ticket::Priority.find_by(name: 'high') || Ticket::Priority.find_by(name: '2 normal') || Ticket::Priority.first,
        preferences: {
          kc_token_alert: true,
          kc_channel_id: channel.id,
          kc_service: service,
        },
        updated_by_id: 1,
        created_by_id: 1,
      ).tap do |ticket|
        create_initial_article(ticket, channel, service, error)
      end
    end

    def update_ticket(ticket, service, error)
      Ticket::Article.create!(
        ticket: ticket,
        from: "System (#{service})",
        to: ALERT_GROUP_NAME,
        subject: "Token refresh still failing",
        body: ticket_update_body(error),
        internal: true,
        type: Ticket::Article::Type.find_by(name: 'note'),
        sender: Ticket::Article::Sender.find_by(name: 'System'),
        updated_by_id: 1,
        created_by_id: 1,
      )
      ticket
    end

    def close_ticket(ticket, service)
      closed_state = Ticket::State.find_by(name: 'closed')
      return if closed_state.nil?

      ticket.update!(
        state: closed_state,
        updated_by_id: 1,
      )

      Ticket::Article.create!(
        ticket: ticket,
        from: "System (#{service})",
        to: ALERT_GROUP_NAME,
        subject: "Token refresh successful",
        body: "Authentication has been restored. Token refresh is now working correctly.",
        internal: true,
        type: Ticket::Article::Type.find_by(name: 'note'),
        sender: Ticket::Article::Sender.find_by(name: 'System'),
        updated_by_id: 1,
        created_by_id: 1,
      )
    end

    def create_initial_article(ticket, channel, service, error)
      Ticket::Article.create!(
        ticket: ticket,
        from: "System (#{service})",
        to: ALERT_GROUP_NAME,
        subject: "Token refresh failure detected",
        body: ticket_body(channel, service, error),
        internal: true,
        type: Ticket::Article::Type.find_by(name: 'note'),
        sender: Ticket::Article::Sender.find_by(name: 'System'),
        updated_by_id: 1,
        created_by_id: 1,
      )
    end

    def alert_ticket_title(service, channel)
      "#{service} OAuth Token Expired - #{channel.options[:name] || channel.area}"
    end

    def ticket_body(channel, service, error)
      <<~BODY
        The OAuth token for #{service} channel '#{channel.options[:name] || channel.area}' has failed to refresh.

        Error: #{error}

        This typically means the refresh token has expired or been revoked. Messages cannot be sent or received until this is resolved.

        ACTION REQUIRED:
        1. Go to Admin → Channels
        2. Find the #{service} channel: #{channel.options[:name] || channel.area}
        3. Click 'Re-authenticate' or 'Edit'
        4. Complete the OAuth authorization flow again

        Channel ID: #{channel.id}
        Channel Area: #{channel.area}
        Failed At: #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}
      BODY
    end

    def ticket_update_body(error)
      <<~BODY
        Token refresh is still failing.

        Latest Error: #{error}
        Time: #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}

        Please re-authenticate this channel as soon as possible.
      BODY
    end
  end
end
