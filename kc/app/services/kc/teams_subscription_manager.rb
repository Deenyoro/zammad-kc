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
  EXPIRATION_MINUTES = 55   # Graph max for chat resources is ~60 min
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

    existing = sub_class.find_by(channel: channel, chat_id: chat_id)

    if existing && existing.expires_at > Time.current
      return existing
    end

    # Remove expired record if present
    existing&.destroy

    create_subscription(chat_id)
  end

  # Renews all subscriptions for this channel that are expiring soon.
  def renew_expiring_subscriptions
    sub_class = subscription_class
    return if sub_class.nil?

    graph = build_graph_client
    return if graph.nil?

    graph.refresh_access_token!
    persist_tokens(graph)

    subs = sub_class.where(channel: channel).expiring_soon(within: RENEW_WINDOW.minutes)

    subs.find_each do |sub|
      renew_single(graph, sub)
    rescue => e
      Rails.logger.error "KC Teams: Failed to renew subscription #{sub.subscription_id}: #{e.message}"
    end
  end

  # Deletes all subscriptions for this channel (e.g. on channel removal).
  def cleanup_channel_subscriptions
    sub_class = subscription_class
    return if sub_class.nil?

    graph = build_graph_client
    if graph
      begin
        graph.refresh_access_token!
      rescue => e
        Rails.logger.warn "KC Teams: Token refresh failed during cleanup: #{e.message}"
      end
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
    graph = build_graph_client
    return nil if graph.nil?

    graph.refresh_access_token!
    persist_tokens(graph)

    client_state     = SecureRandom.hex(32)
    notification_url = webhook_url

    result = graph.create_subscription(
      chat_id,
      notification_url,
      client_state,
      expiration_minutes: EXPIRATION_MINUTES,
    )

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

  def build_graph_client
    graph_class = 'Kc::MicrosoftTeamsGraph'.safe_constantize
    if graph_class.nil?
      Rails.logger.error 'KC Teams: MicrosoftTeamsGraph class not found'
      return nil
    end

    opts = channel.options
    graph_class.new(
      client_id:     opts[:client_id],
      client_secret: opts[:client_secret],
      tenant_id:     opts[:tenant_id],
      access_token:  opts[:access_token],
      refresh_token: opts[:refresh_token],
    )
  end

  def persist_tokens(graph)
    channel.options[:access_token]  = graph.access_token
    channel.options[:refresh_token] = graph.refresh_token
    channel.save!
  rescue => e
    Rails.logger.error "KC Teams: Failed to persist tokens for channel #{channel.id}: #{e.message}"
  end
end
