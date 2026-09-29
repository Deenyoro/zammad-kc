# KC: Public webhook endpoint for text messages pushed by the FreePBX
# connector (see Kc::FreepbxApi for the payload).
#
# Authentication: the connector sends its connection token in the
# X-KC-Token header (or as a bearer token). The token identifies the
# connection; a request whose token matches no active connection is
# dropped. The token is the same shared secret the connection already
# uses in the other direction, so nothing new has to be configured on
# the PBX beyond the webhook URL.
#
# Always answers 200 once the token matched so the connector does not
# retry a message Zammad has already queued.
class Kc::FreepbxSmsWebhookController < ApplicationController
  skip_before_action :verify_csrf_token, only: [:webhook]
  prepend_before_action :authenticate_and_authorize!, except: [:webhook]

  # POST /api/v1/kc/freepbx_sms_webhook
  def webhook
    token = request.headers['X-KC-Token'].presence ||
            request.headers['HTTP_X_KC_TOKEN'].presence ||
            request.authorization.to_s[/\ABearer\s+(.+)\z/i, 1]
    if token.blank?
      render json: { error: 'missing token' }, status: :unauthorized
      return
    end

    channel = Channel.where(area: 'Freepbx::Account', active: true).detect do |c|
      stored = c.options.with_indifferent_access[:token].to_s
      stored.present? && ActiveSupport::SecurityUtils.secure_compare(stored, token.to_s)
    end
    if channel.nil?
      Rails.logger.warn 'KC FreePBX SMS Webhook: token matched no active connection'
      render json: { error: 'unknown connection' }, status: :unauthorized
      return
    end

    if Setting.get('kc_freepbx_sms_enabled') != true
      render json: { ok: true, ignored: 'texting disabled' }, status: :ok
      return
    end

    job_class = 'Kc::ProcessFreepbxSmsWebhookJob'.safe_constantize
    if job_class.nil?
      Rails.logger.error 'KC FreePBX SMS Webhook: ProcessFreepbxSmsWebhookJob class not found'
      render json: { ok: true }, status: :ok
      return
    end

    payload  = params.to_unsafe_h.with_indifferent_access
    messages = payload[:messages].is_a?(Array) ? payload[:messages] : [payload]
    queued   = 0
    messages.each do |message|
      message = message.to_h.with_indifferent_access.except(:controller, :action, :format, :freepbx_sms_webhook)
      next if message[:id].blank? && message[:from].blank?

      job_class.perform_later(channel_id: channel.id, message: message.to_h)
      queued += 1
    end

    render json: { ok: true, queued: queued }, status: :ok
  rescue => e
    Rails.logger.error "KC FreePBX SMS Webhook: Unhandled error: #{e.message}"
    render json: { ok: true }, status: :ok
  end
end
