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

    rc = rc_class.with_channel_tokens(channel)
    from_phone = channel.options.with_indifferent_access[:phone_number]
    # Strip HTML tags — Zammad stores article bodies as HTML but SMS needs plain text.
    body_text  = article.body.present? ? ActionController::Base.helpers.strip_tags(article.body).strip : ''

    # Step 1: Send text as plain SMS (always, even if attachments exist)
    sms_result = nil
    if body_text.present?
      sms_result = rc.send_sms(from: from_phone, to: to_phone, text: body_text)
    end

    # Step 2: Send attachments as separate MMS messages (no text body)
    mms_message_ids = []
    attachments = article.attachments
    if attachments.any?
      attachments.each do |store|
        begin
          att_data = [{
            filename:     store.filename,
            content_type: store.preferences&.dig('Content-Type') || 'application/octet-stream',
            data:         store.content,
          }]
          mms_result = rc.send_mms(from: from_phone, to: to_phone, text: '', attachments: att_data)
          mms_id = mms_result && (mms_result['id'] || mms_result[:id])
          mms_message_ids << mms_id.to_s if mms_id.present?
        rescue => e
          Rails.logger.error "KC RingCentral SMS Job: Failed to send attachment #{store.filename} for article #{article_id}: #{e.message}"
          # Continue sending remaining attachments
        end
      end
    end

    # Store the returned RC message ID(s) on the article for dedup.
    # The poll job uses these to avoid creating ghost outbound captures
    # for MMS companion messages.
    rc_message_id = sms_result && (sms_result['id'] || sms_result[:id])
    article.message_id = "rc_sms:#{rc_message_id}" if rc_message_id.present?
    article.preferences[:ringcentral_sms] ||= {}
    article.preferences[:ringcentral_sms][:rc_message_id]    = rc_message_id
    article.preferences[:ringcentral_sms][:mms_message_ids]  = mms_message_ids if mms_message_ids.any?
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
end
