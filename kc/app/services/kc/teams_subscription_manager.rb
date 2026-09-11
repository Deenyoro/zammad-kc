# KC: Manages Microsoft Graph webhook subscriptions for Teams chat channels.
#
# Responsibilities:
#   - Create new subscriptions for chats
#   - Renew expiring subscriptions
#   - Delete subscriptions when channels are removed
#   - Handle token refresh before Graph API calls
#
# Safety:
#   - safe_constantize on all KC classes
#   - Per-subscription rescue in renewal loop
#   - 404 detection with automatic recreation
#
# Usage:
#   manager = Kc::TeamsSubscriptionManager.new(channel)
#   manager.ensure_subscription(chat_id)
#   manager.renew_expiring_subscriptions
#   manager.cleanup_channel_subscriptions
#
class Kc::TeamsSubscriptionManager
  EXPIRATION_MINUTES = 55   # Graph max for chatMessage is 4320 min (3 days), but >60 min requires lifecycleNotificationUrl
  RENEW_WINDOW       = 15   # Renew if expiring within this many minutes

  attr_reader :channel

  def initialize(channel)
    @channel = channel
  end

  # Ensures a subscription exists for the given chat_id.
  # Creates one if none exists or the existing one has expired.
  def ensure_subscription(chat_id)
    sub_class = subscription_class
    return nil if sub_class.nil?

    live = sub_class.where(channel: channel, chat_id: chat_id)
                    .where('expires_at > ?', Time.current)
                    .order(expires_at: :desc)
                    .first
    return live if live

    # Every record for this chat is expired (or there is none) — drop them
    # all; expired rows used to pile up by the hundreds.
    sub_class.where(channel: channel, chat_id: chat_id).delete_all

    # No lock around the Graph round-trips: the 30 s poll and the 10 min
    # renewal run on different scheduler threads and holding the channel row
    # while talking to Graph stalled the poll for minutes. If both create for
    # the same chat, the reconcile in create_subscription / prune_orphans
    # removes the extra on the next pass.
    create_subscription(chat_id)
  end

  # Renews all subscriptions for this channel that are expiring soon.
  def renew_expiring_subscriptions
    sub_class = subscription_class
    return if sub_class.nil?

    graph_class = 'Kc::MicrosoftTeamsGraph'.safe_constantize
    return if graph_class.nil?

    begin
      graph = graph_class.with_channel_tokens(channel)
      Kc::TokenAlertService.clear_alerts(channel: channel, service: 'Microsoft Teams')
    rescue => e
      Rails.logger.error "KC Teams: Token refresh failed for channel #{channel.id}: #{e.message}"
      Kc::TokenAlertService.alert_token_failure(
        channel: channel,
        service: 'Microsoft Teams',
        error: e.message
      )
      return
    end

    subs   = sub_class.where(channel: channel).expiring_soon(within: RENEW_WINDOW.minutes)
    wanted = chat_ids_with_open_tickets

    subs.find_each do |sub|
      # Only chats with an open ticket need a webhook; the poll's discovery
      # pass covers everything else. Renewing subscriptions for every chat
      # ever seen is what exhausted Graph's per-user quota.
      if wanted.exclude?(sub.chat_id)
        begin
          graph.delete_subscription(sub.subscription_id)
        rescue => e
          Rails.logger.debug { "KC Teams: delete of retired subscription #{sub.subscription_id} failed: #{e.message}" }
        end
        sub.destroy
        next
      end

      renew_single(graph, sub)
    rescue => e
      Rails.logger.error "KC Teams: Failed to renew subscription #{sub.subscription_id}: #{e.message}"
    end

    prune_orphans(graph)
  end

  # Chats that currently have a ticket that is not closed.
  def chat_ids_with_open_tickets
    closed_state_ids = Ticket::State
                         .joins(:state_type)
                         .where(ticket_state_types: { name: 'closed' })
                         .select(:id)

    Ticket.where('preferences LIKE ?', '%teams_chat%')
          .where.not(state_id: closed_state_ids)
          .select(:id, :preferences)
          .filter_map { |t| t.preferences.dig('teams_chat', 'chat_id') }
          .to_set
  end

  # Runs with every renewal pass (10 min). Drops DB rows that expired and
  # Graph subscriptions pointing at our webhook that no live DB row tracks —
  # those orphans are what exhausts Graph's per-chat subscription cap and, once
  # they exceed the cap, keep every recreate for that chat failing with 403.
  def prune_orphans(graph)
    sub_class = subscription_class
    return if sub_class.nil? || !graph.respond_to?(:list_subscriptions)

    expired = sub_class.where(channel: channel).where('expires_at <= ?', Time.current).delete_all
    Rails.logger.info "KC Teams: Purged #{expired} expired subscription rows for channel #{channel.id}" if expired.positive?

    tracked = sub_class.where(channel: channel).where('expires_at > ?', Time.current).pluck(:subscription_id).to_set
    removed = 0
    graph.list_subscriptions.each do |sub|
      next unless sub['notificationUrl'].to_s == webhook_url
      next unless sub['resource'].to_s.start_with?('/chats/')
      next if tracked.include?(sub['id'].to_s)

      begin
        graph.delete_subscription(sub['id'])
        removed += 1
      rescue => e
        Rails.logger.warn "KC Teams: Could not remove orphan subscription #{sub['id']}: #{e.message}"
      end
    end
    Rails.logger.info "KC Teams: Removed #{removed} orphaned Graph subscriptions for channel #{channel.id}" if removed.positive?
  rescue => e
    Rails.logger.warn "KC Teams: Orphan prune failed for channel #{channel.id}: #{e.message}"
  end

  # Deletes all subscriptions for this channel (e.g. on channel removal).
  def cleanup_channel_subscriptions
    sub_class = subscription_class
    return if sub_class.nil?

    graph_class = 'Kc::MicrosoftTeamsGraph'.safe_constantize
    graph = begin
              graph_class&.with_channel_tokens(channel)
            rescue => e
              Rails.logger.warn "KC Teams: Token refresh failed during cleanup: #{e.message}"
              nil
            end

    sub_class.where(channel: channel).find_each do |sub|
      if graph
        begin
          graph.delete_subscription(sub.subscription_id)
        rescue => e
          Rails.logger.warn "KC Teams: Failed to delete subscription #{sub.subscription_id}: #{e.message}"
        end
      end
      sub.destroy
    end
  end

  private

  def subscription_class
    klass = 'Kc::TeamsSubscription'.safe_constantize
    if klass.nil? || !klass.table_exists?
      Rails.logger.warn 'KC Teams: Kc::TeamsSubscription not available'
      return nil
    end
    klass
  end

  def create_subscription(chat_id)
    graph_class = 'Kc::MicrosoftTeamsGraph'.safe_constantize
    return nil if graph_class.nil?

    begin
      graph = graph_class.with_channel_tokens(channel)
      Kc::TokenAlertService.clear_alerts(channel: channel, service: 'Microsoft Teams')
    rescue => e
      Rails.logger.error "KC Teams: Token refresh failed for channel #{channel.id}: #{e.message}"
      Kc::TokenAlertService.alert_token_failure(
        channel: channel,
        service: 'Microsoft Teams',
        error: e.message
      )
      return nil
    end

    client_state     = SecureRandom.hex(32)
    notification_url = webhook_url

    # Graph allows only a handful of chatMessage subscriptions per user and
    # chat, and every one we lost track of (renewal 404 after a missed cycle,
    # a crash between create and save) still counts. Clear ours for this chat
    # before creating; if Graph still refuses, clear again and retry once.
    remove_graph_subscriptions_for(graph, chat_id)

    result = begin
      graph.create_subscription(chat_id, notification_url, client_state, expiration_minutes: EXPIRATION_MINUTES)
    rescue => e
      raise unless e.message.to_s =~ /limit|403/i

      Rails.logger.warn "KC Teams: Graph refused subscription for chat #{chat_id} (#{e.message.truncate(120)}), clearing and retrying"
      remove_graph_subscriptions_for(graph, chat_id, force_list: true)
      graph.create_subscription(chat_id, notification_url, client_state, expiration_minutes: EXPIRATION_MINUTES)
    end

    sub_class = subscription_class
    return nil if sub_class.nil?

    sub_class.create!(
      channel:         channel,
      chat_id:         chat_id,
      subscription_id: result['id'] || result[:id],
      client_state:    client_state,
      expires_at:      parse_expiration(result),
    )
  end

  # Deletes every Graph subscription for this chat's messages that points at
  # our webhook. The list is fetched once per manager instance (one poll
  # cycle) unless force_list is set.
  def remove_graph_subscriptions_for(graph, chat_id, force_list: false)
    return unless graph.respond_to?(:list_subscriptions)

    @graph_subscriptions = nil if force_list
    @graph_subscriptions ||= graph.list_subscriptions
    resource = "/chats/#{chat_id}/messages"
    ours     = @graph_subscriptions.select do |sub|
      sub['resource'].to_s == resource && sub['notificationUrl'].to_s == webhook_url
    end
    return if ours.empty?

    ours.each do |sub|
      graph.delete_subscription(sub['id'])
      Rails.logger.info "KC Teams: Removed stale Graph subscription #{sub['id']} for chat #{chat_id}"
    rescue => e
      Rails.logger.warn "KC Teams: Could not remove Graph subscription #{sub['id']}: #{e.message}"
    end
    @graph_subscriptions -= ours
  rescue => e
    Rails.logger.warn "KC Teams: Could not list Graph subscriptions: #{e.message}"
  end

  def renew_single(graph, subscription)
    result = graph.renew_subscription(subscription.subscription_id, expiration_minutes: EXPIRATION_MINUTES)

    subscription.update!(
      expires_at: parse_expiration(result),
    )

    Rails.logger.info "KC Teams: Renewed subscription #{subscription.subscription_id} for chat #{subscription.chat_id}"
  rescue => e
    if e.message.to_s.include?('404')
      Rails.logger.warn "KC Teams: Subscription #{subscription.subscription_id} gone (404), recreating..."
      chat_id = subscription.chat_id
      subscription.destroy
      create_subscription(chat_id)
    else
      raise
    end
  end

  def parse_expiration(result)
    raw = result['expirationDateTime'] || result[:expirationDateTime]
    raw.present? ? Time.zone.parse(raw.to_s) : EXPIRATION_MINUTES.minutes.from_now
  end

  def webhook_url
    fqdn      = Setting.get('fqdn')
    http_type = Setting.get('http_type') || 'https'
    "#{http_type}://#{fqdn}/api/v1/kc/teams_chat_webhook"
  end

end
