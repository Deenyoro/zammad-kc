# KC: Public webhook endpoint for RingCentral SMS notifications.
#
# This controller handles:
#   1. RingCentral validation handshake (echo Validation-Token header back)
#   2. SMS notification processing (validate subscription, enqueue job, ACK 200)
#
# Authentication:
#   - No auth required for webhook endpoint
#   - Security is via subscription lookup and client_state validation
#
# Safety:
#   - safe_constantize on KC classes to survive missing files after upgrades
#   - Table existence guard on subscription lookup
#   - Always returns 200 to prevent RingCentral retry storms
class Kc::RingcentralSmsWebhookController < ApplicationController
  skip_before_action :verify_csrf_token, only: [:webhook]
  prepend_before_action :authenticate_and_authorize!, except: [:webhook]

  # POST /api/v1/kc/ringcentral_sms_webhook
  def webhook
    # RingCentral validation handshake: echo Validation-Token header back.
    # This is sent during subscription creation — respond with the same
    # header value to prove we own the endpoint.
    validation_token = request.headers['Validation-Token'] || request.headers['HTTP_VALIDATION_TOKEN']
    if validation_token.present?
      response.headers['Validation-Token'] = validation_token
      render plain: '', status: :ok
      return
    end

    # Rails has already parsed the JSON body into params via middleware.
    # Using request.body.read would return an empty string because the
    # IO stream has already been consumed. Use params directly instead.
    notification = params.to_unsafe_h.with_indifferent_access

    # Guard: if the subscriptions table doesn't exist yet (migration pending),
    # ACK the webhook to prevent retries but skip processing.
    sub_class = 'Kc::RingcentralSubscription'.safe_constantize
    if sub_class.nil? || !sub_class.table_exists?
      Rails.logger.warn 'KC RingCentral Webhook: Kc::RingcentralSubscription not available — skipping'
      render json: {}, status: :ok
      return
    end

    # Validate subscription exists
    subscription_id = notification[:subscriptionId]
    if subscription_id.blank?
      Rails.logger.warn 'KC RingCentral Webhook: Missing subscriptionId in notification'
      render json: {}, status: :ok
      return
    end

    subscription = sub_class.find_by(subscription_id: subscription_id)

    if subscription.nil?
      Rails.logger.warn "KC RingCentral Webhook: Unknown subscription #{subscription_id}"
      render json: {}, status: :ok
      return
    end

    # Enqueue async processing — don't block the webhook response
    job_class = 'Kc::ProcessRingcentralSmsWebhookJob'.safe_constantize
    if job_class.nil?
      Rails.logger.error 'KC RingCentral Webhook: ProcessRingcentralSmsWebhookJob class not found'
      render json: {}, status: :ok
      return
    end

    job_class.perform_later(
      channel_id: subscription.channel_id,
      event_body: notification[:body] || notification,
    )

    render json: {}, status: :ok
  rescue => e
    Rails.logger.error "KC RingCentral Webhook: Unhandled error: #{e.message}"
    render json: {}, status: :ok
  end
end
