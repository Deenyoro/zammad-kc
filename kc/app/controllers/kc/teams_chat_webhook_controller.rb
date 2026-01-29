# KC: Public webhook endpoint for Microsoft Graph change notifications
# on Teams chat messages.
#
# This controller handles:
#   1. Graph validation handshake (returns validationToken as plain text)
#   2. Change notification processing (validates clientState, enqueues job, ACKs 202)
#
# Authentication:
#   - ApplicationController does NOT auto-register authenticate_and_authorize!
#   - We register it with `except: [:webhook]` so the webhook action is public
#     (same pattern as ChannelsTelegramController)
#   - Security is via clientState secret validated against stored subscription records
#
# Safety:
#   - safe_constantize on KC classes to survive missing files after upgrades
#   - Table existence guard on subscription lookup
#   - Always returns 202 to prevent Graph retry storms
class Kc::TeamsChatWebhookController < ApplicationController
  skip_before_action :verify_csrf_token, only: [:webhook]
  prepend_before_action :authenticate_and_authorize!, except: [:webhook]

  # POST /api/v1/kc/teams_chat_webhook
  def webhook
    # Graph validation handshake: return the validationToken as plain text
    if params[:validationToken].present?
      render plain: params[:validationToken], status: :ok
      return
    end

    notifications = params[:value]
    if notifications.blank?
      render json: {}, status: :accepted
      return
    end

    # Guard: if the subscriptions table doesn't exist yet (migration pending),
    # ACK the webhook to prevent retries but skip processing.
    sub_class = 'Kc::TeamsSubscription'.safe_constantize
    if sub_class.nil? || !sub_class.table_exists?
      Rails.logger.warn 'KC Teams Webhook: Kc::TeamsSubscription not available — skipping'
      render json: {}, status: :accepted
      return
    end

    # Process each notification
    Array(notifications).each do |notification|
      notification = notification.to_unsafe_h if notification.respond_to?(:to_unsafe_h)
      notification = notification.with_indifferent_access

      # Validate clientState against stored subscriptions
      subscription = sub_class.find_by(
        subscription_id: notification[:subscriptionId],
      )

      if subscription.nil?
        Rails.logger.warn "KC Teams Webhook: Unknown subscription #{notification[:subscriptionId]}"
        next
      end

      if !ActiveSupport::SecurityUtils.secure_compare(subscription.client_state.to_s, notification[:clientState].to_s)
        Rails.logger.warn "KC Teams Webhook: Invalid clientState for subscription #{notification[:subscriptionId]}"
        next
      end

      # Enqueue async processing — don't block the webhook response
      job_class = 'Kc::ProcessTeamsChatWebhookJob'.safe_constantize
      if job_class.nil?
        Rails.logger.error 'KC Teams Webhook: ProcessTeamsChatWebhookJob class not found'
        next
      end

      job_class.perform_later(
        channel_id:      subscription.channel_id,
        chat_id:         subscription.chat_id,
        resource:        notification[:resource],
        change_type:     notification[:changeType],
        subscription_id: notification[:subscriptionId],
      )
    end

    # Always ACK 202 to prevent Graph retries
    render json: {}, status: :accepted
  rescue => e
    Rails.logger.error "KC Teams Webhook: Unhandled error: #{e.message}"
    # Still ACK to prevent Graph retry storms
    render json: {}, status: :accepted
  end
end
