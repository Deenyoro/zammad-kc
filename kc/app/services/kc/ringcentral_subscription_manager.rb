# KC: Manages RingCentral webhook subscriptions for SMS channels.
#
# Responsibilities:
#   - Create new subscriptions for SMS message-store instant notifications
#   - Renew expiring subscriptions
#   - Delete subscriptions when channels are removed
#   - Handle token refresh before RingCentral API calls
#
# Safety:
#   - safe_constantize on all KC classes
#   - Per-subscription rescue in renewal loop
#   - 404 detection with automatic recreation
#
# Usage:
#   manager = Kc::RingcentralSubscriptionManager.new(channel)
#   manager.ensure_subscription
#   manager.renew_expiring_subscriptions
#   manager.cleanup_channel_subscriptions
#
class Kc::RingcentralSubscriptionManager
  # RingCentral subs can last up to 20 years; we use 7 days and renew every 6h.
  EXPIRATION_SECONDS = 7.days.to_i
  RENEW_WINDOW       = 12 # Renew if expiring within this many hours

  # Event filter for instant SMS notifications on the extension's message store.
  SMS_EVENT_FILTER = '/restapi/v1.0/account/~/extension/~/message-store/instant?type=SMS'.freeze

  attr_reader :channel

  def initialize(channel)
    @channel = channel
  end

  # Ensures a subscription exists for this channel.
  # Creates one if none exists or the existing one has expired.
  def ensure_subscription
    sub_class = subscription_class
    return nil if sub_class.nil?

    existing = sub_class.find_by(channel: channel)

    if existing && existing.expires_at > Time.current
      return existing
    end

    # Remove expired record if present
    existing&.destroy

    create_subscription
  end

  # Renews all subscriptions for this channel that are expiring soon.
  def renew_expiring_subscriptions
    sub_class = subscription_class
    return if sub_class.nil?

    rc_class = 'Kc::RingcentralApi'.safe_constantize
    return if rc_class.nil?

    begin
      rc = rc_class.with_channel_tokens(channel)
      Kc::TokenAlertService.clear_alerts(channel: channel, service: 'RingCentral')
    rescue => e
      Rails.logger.error "KC RingCentral: Token refresh failed for channel #{channel.id}: #{e.message}"
      Kc::TokenAlertService.alert_token_failure(
        channel: channel,
        service: 'RingCentral',
        error: e.message
      )
      return
    end

    subs = sub_class.where(channel: channel).expiring_soon(within: RENEW_WINDOW.hours)

    subs.find_each do |sub|
      renew_single(rc, sub)
    rescue => e
      Rails.logger.error "KC RingCentral: Failed to renew subscription #{sub.subscription_id}: #{e.message}"
    end
  end

  # Deletes all subscriptions for this channel (e.g. on channel removal).
  def cleanup_channel_subscriptions
    sub_class = subscription_class
    return if sub_class.nil?

    rc_class = 'Kc::RingcentralApi'.safe_constantize
    rc = begin
           rc_class&.with_channel_tokens(channel)
         rescue => e
           Rails.logger.warn "KC RingCentral: Token refresh failed during cleanup: #{e.message}"
           nil
         end

    sub_class.where(channel: channel).find_each do |sub|
      if rc
        begin
          rc.delete_subscription(sub.subscription_id)
        rescue => e
          Rails.logger.warn "KC RingCentral: Failed to delete subscription #{sub.subscription_id}: #{e.message}"
        end
      end
      sub.destroy
    end
  end

  private

  def subscription_class
    klass = 'Kc::RingcentralSubscription'.safe_constantize
    if klass.nil? || !klass.table_exists?
      Rails.logger.warn 'KC RingCentral: Kc::RingcentralSubscription not available'
      return nil
    end
    klass
  end

  def create_subscription
    rc_class = 'Kc::RingcentralApi'.safe_constantize
    return nil if rc_class.nil?

    begin
      rc = rc_class.with_channel_tokens(channel)
      Kc::TokenAlertService.clear_alerts(channel: channel, service: 'RingCentral')
    rescue => e
      Rails.logger.error "KC RingCentral: Token refresh failed for channel #{channel.id}: #{e.message}"
      Kc::TokenAlertService.alert_token_failure(
        channel: channel,
        service: 'RingCentral',
        error: e.message
      )
      return nil
    end

    client_state     = SecureRandom.hex(32)
    notification_url = webhook_url

    result = rc.create_subscription(
      notification_url,
      [SMS_EVENT_FILTER],
      expires_in:         EXPIRATION_SECONDS,
      verification_token: client_state,
    )

    sub_class = subscription_class
    return nil if sub_class.nil?

    sub_class.create!(
      channel:         channel,
      subscription_id: result['id'] || result[:id],
      client_state:    client_state,
      expires_at:      parse_expiration(result),
    )
  end

  def renew_single(rc, subscription)
    result = rc.renew_subscription(subscription.subscription_id)

    subscription.update!(
      expires_at: parse_expiration(result),
    )

    Rails.logger.info "KC RingCentral: Renewed subscription #{subscription.subscription_id}"
  rescue => e
    if e.message.to_s.include?('404')
      Rails.logger.warn "KC RingCentral: Subscription #{subscription.subscription_id} gone (404), recreating..."
      subscription.destroy
      create_subscription
    else
      raise
    end
  end

  def parse_expiration(result)
    raw = result['expirationTime'] || result[:expirationTime]
    raw.present? ? Time.zone.parse(raw.to_s) : EXPIRATION_SECONDS.seconds.from_now
  end

  def webhook_url
    fqdn      = Setting.get('fqdn')
    http_type = Setting.get('http_type') || 'https'
    "#{http_type}://#{fqdn}/api/v1/kc/ringcentral_sms_webhook"
  end

end
