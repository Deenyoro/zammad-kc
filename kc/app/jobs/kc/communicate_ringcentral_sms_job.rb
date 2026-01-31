# KC: Sends an agent's reply back via RingCentral SMS/MMS.
#
# Enqueued by the Kc::EnqueueCommunicateRingcentralSmsJob concern on
# Ticket::Article after_create_commit when the article type is
# 'ringcentral_sms_message' and the sender is 'Agent'.
#
# Text and attachments are always sent separately:
#   1. Text body is sent as a plain SMS first (ensures text delivery)
#   2. Each attachment is sent as a separate MMS (no text body)
# This ensures the text message always goes through even if an
# attachment upload fails.
#
# Safety:
#   - safe_constantize on KC classes
#   - Symbol key access for preferences
#   - Delivery status tracking on both success and final failure
class Kc::CommunicateRingcentralSmsJob < ApplicationJob
  retry_on StandardError, wait: 10.seconds, attempts: 3

  def perform(article_id)
    article = Ticket::Article.find_by(id: article_id)
    return if article.nil?

    ticket = article.ticket
    return if ticket.nil?

    # Determine which channel and phone to send to.
    sms_prefs     = ticket.preferences&.dig(:ringcentral_sms) || {}
    article_prefs = article.preferences&.dig(:ringcentral_sms) || {}

    # The "to" phone is the customer's phone (the from_phone on inbound messages)
    to_phone   = article_prefs[:to_phone] || sms_prefs[:from_phone]
    channel_id = article_prefs[:channel_id] || sms_prefs[:channel_id] || find_channel_id(ticket)

    if to_phone.blank? || channel_id.blank?
      Rails.logger.warn "KC RingCentral SMS Job: Missing to_phone or channel_id for article #{article_id}"
      return
    end

    channel = Channel.find_by(id: channel_id, area: 'RingCentralSms::Account')
    if channel.nil?
      Rails.logger.warn "KC RingCentral SMS Job: Channel #{channel_id} not found"
      return
    end

    rc_class = 'Kc::RingcentralApi'.safe_constantize
    if rc_class.nil?
      Rails.logger.error 'KC RingCentral SMS Job: RingcentralApi class not found'
      return
    end

    opts = channel.options.with_indifferent_access
    rc = rc_class.new(
      client_id:     opts[:client_id],
      client_secret: opts[:client_secret],
      access_token:  opts[:access_token],
      refresh_token: opts[:refresh_token],
    )

    rc.refresh_access_token!
    persist_tokens(channel, rc)

    from_phone = opts[:phone_number]
    # Strip HTML tags — Zammad stores article bodies as HTML but SMS needs plain text.
    body_text  = article.body.present? ? ActionController::Base.helpers.strip_tags(article.body).strip : ''

    # Step 1: Send text as plain SMS (always, even if attachments exist)
    sms_result = nil
    if body_text.present?
      sms_result = rc.send_sms(from: from_phone, to: to_phone, text: body_text)
    end

    # Step 2: Send attachments as separate MMS messages (no text body)
    attachments = article.attachments
    if attachments.any?
      attachments.each do |store|
        begin
          att_data = [{
            filename:     store.filename,
            content_type: store.preferences&.dig('Content-Type') || 'application/octet-stream',
            data:         store.content,
          }]
          rc.send_mms(from: from_phone, to: to_phone, text: '', attachments: att_data)
        rescue => e
          Rails.logger.error "KC RingCentral SMS Job: Failed to send attachment #{store.filename} for article #{article_id}: #{e.message}"
          # Continue sending remaining attachments
        end
      end
    end

    # Store the returned RC message ID on the article
    rc_message_id = sms_result && (sms_result['id'] || sms_result[:id])
    article.message_id = "rc_sms:#{rc_message_id}" if rc_message_id.present?
    article.preferences[:ringcentral_sms] ||= {}
    article.preferences[:ringcentral_sms][:rc_message_id]    = rc_message_id
    article.preferences[:ringcentral_sms][:delivery_status]  = 'sent'
    article.preferences[:ringcentral_sms][:sent_at]          = Time.current.iso8601
    article.save!

    Rails.logger.info "KC RingCentral SMS: Sent article #{article_id} to #{to_phone}"
  rescue => e
    Rails.logger.error "KC RingCentral SMS Job: Failed to send article #{article_id}: #{e.message}"

    # Update delivery status on final failure
    if executions >= 3
      begin
        article = Ticket::Article.find_by(id: article_id)
        if article
          article.preferences[:ringcentral_sms] ||= {}
          article.preferences[:ringcentral_sms][:delivery_status] = 'failed'
          article.preferences[:ringcentral_sms][:delivery_error]  = e.message.truncate(500)
          article.save!
        end
      rescue => inner
        Rails.logger.error "KC RingCentral SMS Job: Failed to update delivery status: #{inner.message}"
      end
    end

    raise
  end

  private

  def find_channel_id(ticket)
    customer_sender = Ticket::Article::Sender.find_by(name: 'Customer')
    return nil if customer_sender.nil?

    ticket.articles
          .where(sender_id: customer_sender.id)
          .order(created_at: :desc)
          .each do |art|
      channel_id = art.preferences&.dig(:ringcentral_sms, :channel_id)
      return channel_id if channel_id.present?
    end
    nil
  end

  def persist_tokens(channel, rc)
    channel.with_lock do
      channel.reload
      channel.options[:access_token]  = rc.access_token
      channel.options[:refresh_token] = rc.refresh_token
      channel.save!
    end
  rescue => e
    Rails.logger.error "KC RingCentral SMS Job: Failed to persist tokens: #{e.message}"
  end
end
