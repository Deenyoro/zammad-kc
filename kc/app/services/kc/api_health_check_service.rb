# KC: Proactive API connection health check service.
#
# Checks all monitored channels across three integration areas:
#   - Microsoft Graph Email (MicrosoftGraph::Account)
#   - Microsoft Teams Chat (MicrosoftTeamsChat::Account)
#   - RingCentral SMS (RingCentralSms::Account)
#
# For each channel:
#   1. Refreshes OAuth tokens
#   2. Makes a lightweight API call to verify connectivity
#   3. On failure: creates/updates an alert ticket (24h dedup)
#   4. On success: closes any open alert ticket with a recovery note
#   5. Persists refreshed tokens back to the channel
#
# Follows Kc::TokenAlertService patterns but with independent title patterns
# and configurable ticket settings (group, priority, owner).
class Kc::ApiHealthCheckService
  DEDUP_WINDOW = 24.hours

  def execute
    monitored_ids = Setting.get('kc_api_health_check_monitored_channels')
    return if monitored_ids.blank?

    channels = Channel.where(id: monitored_ids, active: true)
    return if channels.empty?

    Rails.logger.info "KC HealthCheck: Checking #{channels.count} channel(s)"

    channels.find_each do |channel|
      check_channel(channel)
    rescue => e
      Rails.logger.error "KC HealthCheck: Unhandled error for channel #{channel.id}: #{e.message}"
    end
  end

  private

  def check_channel(channel)
    case channel.area
    when 'MicrosoftGraph::Account'
      check_microsoft_graph_email(channel)
    when 'MicrosoftTeamsChat::Account'
      check_teams_chat(channel)
    when 'RingCentralSms::Account'
      check_ringcentral_sms(channel)
    else
      Rails.logger.warn "KC HealthCheck: Unknown area '#{channel.area}' for channel #{channel.id}"
    end
  end

  # ---------------------------------------------------------------------------
  # Microsoft Graph Email
  # ---------------------------------------------------------------------------
  def check_microsoft_graph_email(channel)
    service_name = 'Microsoft Graph Email'

    # Refresh OAuth token — method may not exist in all Zammad versions
    if channel.respond_to?(:refresh_xoauth2!)
      channel.refresh_xoauth2!(force: true)
    end

    # Verify mailbox access with a minimal API call
    mailbox = channel.options.dig(:inbound, :options, :user) || channel.options.dig(:outbound, :options, :user)
    access_token = channel.options.dig(:auth, :access_token) || channel.options.dig(:outbound, :options, :password)

    raise 'No mailbox or access token configured' if mailbox.blank? || access_token.blank?

    graph_class = 'MicrosoftGraph'.safe_constantize
    raise 'MicrosoftGraph class not available' if graph_class.nil?

    graph = graph_class.new(access_token: access_token, mailbox: mailbox)
    graph.list_messages(per_page: 1, follow_pagination: false)

    Rails.logger.info "KC HealthCheck: #{service_name} channel #{channel.id} — OK"
    clear_alerts(channel, service_name)
  rescue => e
    Rails.logger.error "KC HealthCheck: #{service_name} channel #{channel.id} — FAILED: #{e.message}"
    create_alert(channel, service_name, e.message)
  end

  # ---------------------------------------------------------------------------
  # Microsoft Teams Chat
  # ---------------------------------------------------------------------------
  def check_teams_chat(channel)
    service_name = 'Teams Chat'
    graph_class = 'Kc::MicrosoftTeamsGraph'.safe_constantize

    if graph_class.nil?
      Rails.logger.warn "KC HealthCheck: MicrosoftTeamsGraph class not available"
      return
    end

    # Atomic token refresh + verify user access
    graph = graph_class.with_channel_tokens(channel, force_refresh: true)
    graph.me

    Rails.logger.info "KC HealthCheck: #{service_name} channel #{channel.id} — OK"
    clear_alerts(channel, service_name)
  rescue => e
    Rails.logger.error "KC HealthCheck: #{service_name} channel #{channel.id} — FAILED: #{e.message}"
    create_alert(channel, service_name, e.message)
  end

  # ---------------------------------------------------------------------------
  # RingCentral SMS
  # ---------------------------------------------------------------------------
  def check_ringcentral_sms(channel)
    service_name = 'RingCentral SMS'
    rc_class = 'Kc::RingcentralApi'.safe_constantize

    if rc_class.nil?
      Rails.logger.warn "KC HealthCheck: RingcentralApi class not available"
      return
    end

    # Force refresh to verify the token is actually valid
    rc = rc_class.with_channel_tokens(channel, force_refresh: true)

    # Verify extension access
    rc.extension_info

    Rails.logger.info "KC HealthCheck: #{service_name} channel #{channel.id} — OK"
    clear_alerts(channel, service_name)
  rescue => e
    Rails.logger.error "KC HealthCheck: #{service_name} channel #{channel.id} — FAILED: #{e.message}"
    create_alert(channel, service_name, e.message)
  end

  # ---------------------------------------------------------------------------
  # Token persistence
  # ---------------------------------------------------------------------------
  def persist_tokens(channel, access_token:, refresh_token:)
    channel.with_lock do
      channel.reload
      channel.options[:access_token]  = access_token
      channel.options[:refresh_token] = refresh_token
      channel.save!
    end
  rescue => e
    Rails.logger.error "KC HealthCheck: Failed to persist tokens for channel #{channel.id}: #{e.message}"
  end

  # ---------------------------------------------------------------------------
  # Alert ticket management
  # ---------------------------------------------------------------------------
  def create_alert(channel, service_name, error)
    return unless should_alert?(channel, service_name)

    title = alert_ticket_title(service_name, channel)
    existing = find_open_alert_ticket(title)

    if existing
      add_failure_note(existing, service_name, error)
    else
      create_alert_ticket(channel, service_name, error, title)
    end

    record_alert(channel, service_name)
  rescue => e
    Rails.logger.error "KC HealthCheck: Failed to create alert ticket: #{e.message}"
  end

  def clear_alerts(channel, service_name)
    title = alert_ticket_title(service_name, channel)
    open_state_ids = Ticket::State.where(name: %w[new open]).pluck(:id)
    return if open_state_ids.empty?

    closed_state = Ticket::State.find_by(name: 'closed')
    return if closed_state.nil?

    Ticket.where(title: title, state_id: open_state_ids).find_each do |ticket|
      ticket.update!(state: closed_state, updated_by_id: 1)

      Ticket::Article.create!(
        ticket:        ticket,
        from:          "System (#{service_name})",
        to:            alert_group&.name || 'System',
        subject:       'Connection restored',
        body:          "API health check for #{service_name} is now passing. Connection has been restored.\n\nTime: #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}",
        internal:      true,
        type:          Ticket::Article::Type.find_by(name: 'note'),
        sender:        Ticket::Article::Sender.find_by(name: 'System'),
        updated_by_id: 1,
        created_by_id: 1,
      )
    end
  rescue => e
    Rails.logger.warn "KC HealthCheck: Failed to close alert tickets: #{e.message}"
  end

  # ---------------------------------------------------------------------------
  # Dedup helpers
  # ---------------------------------------------------------------------------
  def should_alert?(channel, service_name)
    cache_key = "kc_api_health_check:#{service_name.parameterize}:#{channel.id}"
    last_alert = Rails.cache.read(cache_key)
    last_alert.nil? || last_alert < DEDUP_WINDOW.ago
  end

  def record_alert(channel, service_name)
    cache_key = "kc_api_health_check:#{service_name.parameterize}:#{channel.id}"
    Rails.cache.write(cache_key, Time.current, expires_in: DEDUP_WINDOW)
  end

  # ---------------------------------------------------------------------------
  # Ticket helpers
  # ---------------------------------------------------------------------------
  def alert_ticket_title(service_name, channel)
    account_name = channel.options[:name] || channel.options[:user_display_name] || channel.options.dig(:inbound, :options, :user) || channel.area
    "API Health Check Failed - #{service_name} - #{account_name}"
  end

  def find_open_alert_ticket(title)
    open_state_ids = Ticket::State.where(name: %w[new open]).pluck(:id)
    Ticket.where(title: title, state_id: open_state_ids).order(created_at: :desc).first
  end

  def create_alert_ticket(channel, service_name, error, title)
    group    = alert_group
    priority = alert_priority
    owner_id = Setting.get('kc_api_health_check_owner_id')

    attrs = {
      title:         title,
      group:         group,
      customer_id:   1, # System user
      state:         Ticket::State.find_by(name: 'new'),
      priority:      priority,
      updated_by_id: 1,
      created_by_id: 1,
      preferences:   {
        kc_api_health_check: true,
        kc_channel_id:       channel.id,
        kc_service:          service_name,
      },
    }
    attrs[:owner_id] = owner_id if owner_id.present?

    ticket = Ticket.create!(attrs)

    Ticket::Article.create!(
      ticket:        ticket,
      from:          "System (#{service_name})",
      to:            group.name,
      subject:       'API health check failure detected',
      body:          alert_body(channel, service_name, error),
      internal:      true,
      type:          Ticket::Article::Type.find_by(name: 'note'),
      sender:        Ticket::Article::Sender.find_by(name: 'System'),
      updated_by_id: 1,
      created_by_id: 1,
    )

    ticket
  end

  def add_failure_note(ticket, service_name, error)
    Ticket::Article.create!(
      ticket:        ticket,
      from:          "System (#{service_name})",
      to:            alert_group.name,
      subject:       'Health check still failing',
      body:          "API health check is still failing.\n\nLatest Error: #{error}\nTime: #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}\n\nPlease investigate and re-authenticate if necessary.",
      internal:      true,
      type:          Ticket::Article::Type.find_by(name: 'note'),
      sender:        Ticket::Article::Sender.find_by(name: 'System'),
      updated_by_id: 1,
      created_by_id: 1,
    )
    ticket
  end

  def alert_group
    group_id = Setting.get('kc_api_health_check_group_id')
    (group_id.present? && Group.find_by(id: group_id)) || Group.find_by(name: 'Users') || Group.first
  end

  def alert_priority
    priority_id = Setting.get('kc_api_health_check_priority_id')
    (priority_id.present? && Ticket::Priority.find_by(id: priority_id)) || Ticket::Priority.find_by(name: '3 high') || Ticket::Priority.find_by(name: '2 normal')
  end

  def alert_body(channel, service_name, error)
    account_name = channel.options[:name] || channel.options[:user_display_name] || channel.options.dig(:inbound, :options, :user) || channel.area

    <<~BODY
      The API health check for #{service_name} channel '#{account_name}' has failed.

      Error: #{error}

      This means the API connection may be broken. Messages may not be sent or received until this is resolved.

      ACTION REQUIRED:
      1. Go to Admin → Channels or KC Extensions
      2. Find the #{service_name} channel: #{account_name}
      3. Click 'Re-authenticate' or 'Edit'
      4. Complete the OAuth authorization flow again

      Channel ID: #{channel.id}
      Channel Area: #{channel.area}
      Failed At: #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}
    BODY
  end
end
