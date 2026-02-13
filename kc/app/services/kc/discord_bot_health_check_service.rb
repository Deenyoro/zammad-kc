# frozen_string_literal: true

# KC: Discord bot health check service.
#
# Polls the Discord bot's /healthz endpoint at a configurable interval.
# After N consecutive failures (configurable threshold), creates an alert
# ticket. On recovery, closes any open alert tickets with a note.
#
# Uses Rails.cache for failure count tracking (survives scheduler cycles,
# resets on pod restart which is fine — bot would restart too).
#
# Follows the same alert ticket patterns as Kc::ApiHealthCheckService.
class Kc::DiscordBotHealthCheckService
  CACHE_KEY         = 'kc_discord_bot_health_check:failures'
  LAST_CHECK_KEY    = 'kc_discord_bot_health_check:last_check'
  DEDUP_WINDOW      = 24.hours
  ALERT_TITLE       = 'Discord Bot Health Check Failed'

  def execute
    return unless enabled?
    return if checked_too_recently?

    Rails.cache.write(LAST_CHECK_KEY, Time.current, expires_in: 1.hour)
    perform_check
  end

  private

  # ---------------------------------------------------------------------------
  # Settings
  # ---------------------------------------------------------------------------
  def enabled?
    Setting.get('kc_discord_bot_health_check_enabled') == true
  end

  def health_url
    Setting.get('kc_discord_bot_health_check_url').presence || 'http://zammad-discord-bot:3100/healthz'
  end

  def failure_threshold
    val = Setting.get('kc_discord_bot_health_check_failure_threshold')
    val = val.to_i if val.is_a?(String)
    val.is_a?(Integer) && val > 0 ? val : 4
  end

  def check_interval
    val = Setting.get('kc_discord_bot_health_check_interval')
    val = val.to_i if val.is_a?(String)
    val.is_a?(Integer) && val > 0 ? val : 30
  end

  # The Scheduler fires every 30s but the admin may want a longer interval.
  # Skip this run if we checked more recently than the configured interval.
  def checked_too_recently?
    last_check = Rails.cache.read(LAST_CHECK_KEY)
    return false if last_check.nil?

    last_check > check_interval.seconds.ago
  end

  # ---------------------------------------------------------------------------
  # Core check
  # ---------------------------------------------------------------------------
  def perform_check
    url = health_url

    begin
      response = UserAgent.get(
        url,
        {},
        {
          open_timeout:  5,
          read_timeout:  5,
          total_timeout: 10,
          log:           { facility: 'kc_discord_health' },
        },
      )
      success = response.success?
    rescue => e
      Rails.logger.error "KC DiscordBotHealthCheck: Request error: #{e.message}"
      success = false
    end

    if success
      handle_success
    else
      error_msg = success == false && defined?(response) && response ? "HTTP #{response.code}" : 'Connection failed'
      handle_failure(error_msg)
    end
  end

  # ---------------------------------------------------------------------------
  # Success / failure handling
  # ---------------------------------------------------------------------------
  def handle_success
    count = Rails.cache.read(CACHE_KEY).to_i
    Rails.cache.delete(CACHE_KEY)

    # Only attempt to close alert tickets when transitioning from failure → success.
    # Avoids unnecessary DB queries on every healthy check cycle.
    return if count.zero?

    Rails.logger.info "KC DiscordBotHealthCheck: Bot is healthy again (was at #{count} consecutive failures)"
    clear_alerts
  end

  def handle_failure(error_msg)
    count = (Rails.cache.read(CACHE_KEY) || 0).to_i + 1
    Rails.cache.write(CACHE_KEY, count, expires_in: 1.hour)

    threshold = failure_threshold
    Rails.logger.warn "KC DiscordBotHealthCheck: Failure #{count}/#{threshold} — #{error_msg}"

    return if count < threshold

    create_alert(error_msg, count)
  end

  # ---------------------------------------------------------------------------
  # Alert ticket management
  # ---------------------------------------------------------------------------
  def create_alert(error_msg, failure_count)
    return unless should_alert?

    existing = find_open_alert_ticket
    if existing
      add_failure_note(existing, error_msg, failure_count)
    else
      create_alert_ticket(error_msg, failure_count)
    end

    record_alert
  rescue => e
    Rails.logger.error "KC DiscordBotHealthCheck: Failed to create alert ticket: #{e.message}"
  end

  def clear_alerts
    open_state_ids = Ticket::State.where(name: %w[new open]).pluck(:id)
    return if open_state_ids.empty?

    closed_state = Ticket::State.find_by(name: 'closed')
    return if closed_state.nil?

    Ticket.where(title: ALERT_TITLE, state_id: open_state_ids).find_each do |ticket|
      ticket.update!(state: closed_state, updated_by_id: 1)

      Ticket::Article.create!(
        ticket:        ticket,
        from:          'System (Discord Bot)',
        to:            alert_group&.name || 'System',
        subject:       'Bot recovered',
        body:          "Discord bot health check is now passing. The bot has recovered.\n\nTime: #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}",
        internal:      true,
        type:          Ticket::Article::Type.find_by(name: 'note') || Ticket::Article::Type.first,
        sender:        Ticket::Article::Sender.find_by(name: 'System') || Ticket::Article::Sender.first,
        updated_by_id: 1,
        created_by_id: 1,
      )
    end
  rescue => e
    Rails.logger.warn "KC DiscordBotHealthCheck: Failed to close alert tickets: #{e.message}"
  end

  # ---------------------------------------------------------------------------
  # Dedup helpers
  # ---------------------------------------------------------------------------
  def should_alert?
    cache_key = 'kc_discord_bot_health_check:last_alert'
    last_alert = Rails.cache.read(cache_key)
    last_alert.nil? || last_alert < DEDUP_WINDOW.ago
  end

  def record_alert
    Rails.cache.write('kc_discord_bot_health_check:last_alert', Time.current, expires_in: DEDUP_WINDOW)
  end

  # ---------------------------------------------------------------------------
  # Ticket helpers
  # ---------------------------------------------------------------------------
  def find_open_alert_ticket
    open_state_ids = Ticket::State.where(name: %w[new open]).pluck(:id)
    Ticket.where(title: ALERT_TITLE, state_id: open_state_ids).order(created_at: :desc).first
  end

  def create_alert_ticket(error_msg, failure_count)
    group = alert_group
    priority = alert_priority

    if group.nil?
      Rails.logger.error 'KC DiscordBotHealthCheck: Cannot create alert ticket — no group available'
      return nil
    end

    owner_id = Setting.get('kc_discord_bot_health_check_owner_id')
    threshold = failure_threshold
    interval = Setting.get('kc_discord_bot_health_check_interval') || 30

    attrs = {
      title:         ALERT_TITLE,
      group:         group,
      customer_id:   1,
      state:         Ticket::State.find_by(name: 'new') || Ticket::State.first,
      priority:      priority || Ticket::Priority.first,
      updated_by_id: 1,
      created_by_id: 1,
      preferences:   {
        kc_discord_bot_health_check: true,
      },
    }
    attrs[:owner_id] = owner_id if owner_id.present?

    ticket = Ticket.create!(attrs)

    Ticket::Article.create!(
      ticket:        ticket,
      from:          'System (Discord Bot)',
      to:            group.name,
      subject:       'Discord bot is down',
      body:          alert_body(error_msg, failure_count, threshold, interval),
      internal:      true,
      type:          Ticket::Article::Type.find_by(name: 'note') || Ticket::Article::Type.first,
      sender:        Ticket::Article::Sender.find_by(name: 'System') || Ticket::Article::Sender.first,
      updated_by_id: 1,
      created_by_id: 1,
    )

    ticket
  end

  def add_failure_note(ticket, error_msg, failure_count)
    Ticket::Article.create!(
      ticket:        ticket,
      from:          'System (Discord Bot)',
      to:            alert_group&.name || 'System',
      subject:       'Bot still down',
      body:          "Discord bot health check is still failing.\n\nLatest Error: #{error_msg}\nConsecutive Failures: #{failure_count}\nTime: #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}\n\nPlease investigate.",
      internal:      true,
      type:          Ticket::Article::Type.find_by(name: 'note') || Ticket::Article::Type.first,
      sender:        Ticket::Article::Sender.find_by(name: 'System') || Ticket::Article::Sender.first,
      updated_by_id: 1,
      created_by_id: 1,
    )
    ticket
  end

  def alert_group
    group_id = Setting.get('kc_discord_bot_health_check_group_id')
    return Group.find_by(id: group_id) if group_id.present? && Group.exists?(id: group_id)

    # Fall back to the API health check group, then Users, then first
    api_group_id = Setting.get('kc_api_health_check_group_id')
    return Group.find_by(id: api_group_id) if api_group_id.present? && Group.exists?(id: api_group_id)

    Group.find_by(name: 'Users') || Group.first
  end

  def alert_priority
    priority_id = Setting.get('kc_discord_bot_health_check_priority_id')
    return Ticket::Priority.find_by(id: priority_id) if priority_id.present? && Ticket::Priority.exists?(id: priority_id)

    # Default to highest available priority
    Ticket::Priority.where(active: true).order(id: :desc).first || Ticket::Priority.find_by(name: '3 high') || Ticket::Priority.first
  end

  def alert_body(error_msg, failure_count, threshold, interval)
    downtime_seconds = failure_count * interval.to_i
    downtime_minutes = (downtime_seconds / 60.0).round(1)

    <<~BODY
      The Discord bot health check has failed #{failure_count} consecutive times (threshold: #{threshold}).

      Error: #{error_msg}
      Health URL: #{health_url}
      Estimated Downtime: ~#{downtime_minutes} minutes

      The Discord bot may be down or unreachable. Discord messages will NOT be processed until the bot recovers.

      ACTION REQUIRED:
      1. Check the Discord bot pod/container status
      2. Review Discord bot logs for errors
      3. Restart the bot if necessary

      Failed At: #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}
    BODY
  end
end
