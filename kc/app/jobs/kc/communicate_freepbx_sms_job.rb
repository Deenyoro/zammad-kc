# KC: Sends an agent's reply back as a text through the FreePBX connector.
#
# Enqueued by the Kc::EnqueueCommunicateFreepbxSmsJob concern on
# Ticket::Article after_create_commit when the article type is
# 'freepbx_sms_message' and the sender is 'Agent'.
#
# Text and attachments are sent separately: the text first as plain SMS,
# then each attachment as its own MMS, so the words always go through even
# if a media upload fails.
#
# Safety:
#   - safe_constantize on KC classes
#   - Delivery status tracking on both success and final failure
class Kc::CommunicateFreepbxSmsJob < ApplicationJob
  retry_on StandardError, wait: 10.seconds, attempts: 3

  PREFS_KEY = :freepbx_sms

  def perform(article_id)
    article = Ticket::Article.find_by(id: article_id)
    return if article.nil?

    ticket = article.ticket
    return if ticket.nil?

    # retry_on re-runs this job after a timeout even when the connector
    # already accepted the message; never send the same article twice.
    if article.preferences&.dig(PREFS_KEY, :delivery_status) == 'sent'
      Rails.logger.info "KC FreePBX SMS Job: Article #{article_id} already sent — skipping"
      return
    end

    sms_prefs     = ticket.preferences&.dig(PREFS_KEY) || {}
    article_prefs = article.preferences&.dig(PREFS_KEY) || {}

    to_phones  = Array(article_prefs[:to_phones]).compact_blank.presence ||
                 Array(sms_prefs[:participants]).compact_blank.presence ||
                 [article_prefs[:to_phone] || sms_prefs[:from_phone]].compact_blank
    channel_id = article_prefs[:channel_id] || sms_prefs[:channel_id] || find_channel_id(ticket)

    if to_phones.empty? || channel_id.blank?
      Rails.logger.warn "KC FreePBX SMS Job: Missing recipient or channel_id for article #{article_id}"
      return
    end

    channel = Channel.find_by(id: channel_id, area: 'Freepbx::Account')
    if channel.nil?
      Rails.logger.warn "KC FreePBX SMS Job: Channel #{channel_id} not found"
      return
    end

    # Reply from the number the customer texted; a different number forks
    # the thread on their phone and spawns a duplicate ticket here.
    from_phone = article_prefs[:from_phone].presence ||
                 sms_prefs[:to_phone].presence ||
                 find_our_phone(ticket).presence

    driver    = Channel::Driver::KcFreepbx.new
    body_text = plain_text(article.body)

    sms_result = nil
    if body_text.present?
      sms_result = driver.deliver(channel.options, { body: body_text, to_phones: to_phones, from_phone: from_phone }, channel: channel)
    end

    mms_message_ids = []
    article.attachments.each do |store|
      media = [{
        filename:     store.filename,
        content_type: store.preferences&.dig('Content-Type') || 'application/octet-stream',
        data_base64:  [store.content].pack('m0'),
      }]
      mms_result = driver.deliver(channel.options, { body: '', to_phones: to_phones, from_phone: from_phone, media: media }, channel: channel)
      mms_id = mms_result && (mms_result['id'] || mms_result[:id])
      mms_message_ids << mms_id.to_s if mms_id.present?
    rescue StandardError => e
      Rails.logger.error "KC FreePBX SMS Job: Failed to send attachment #{store.filename} for article #{article_id}: #{e.message}"
    end

    message_id = sms_result && (sms_result['id'] || sms_result[:id])
    article.message_id = "#{Channel::Driver::KcFreepbx::DEDUP_PREFIX}#{message_id}" if message_id.present?
    article.preferences[PREFS_KEY] ||= {}
    article.preferences[PREFS_KEY][:pbx_message_id]  = message_id
    article.preferences[PREFS_KEY][:mms_message_ids] = mms_message_ids if mms_message_ids.any?
    article.preferences[PREFS_KEY][:delivery_status] = 'sent'
    article.preferences[PREFS_KEY][:sent_at]         = Time.current.iso8601
    article.preferences[PREFS_KEY][:from_phone]      = from_phone
    article.preferences[PREFS_KEY][:to_phone]        = to_phones.first
    article.preferences[PREFS_KEY][:to_phones]       = to_phones if to_phones.size > 1
    article.preferences[PREFS_KEY][:channel_id]      = channel.id
    article.save!

    # MMS companions come back through the outbound poll under their own
    # ids; recording them keeps the poll from filing them as agent notes.
    sms_class = 'Kc::OutboundSms'.safe_constantize
    if sms_class.respond_to?(:remember_system_message)
      mms_message_ids.each { |id| sms_class.remember_system_message(channel, id) }
    end

    Rails.logger.info "KC FreePBX SMS: Sent article #{article_id} to #{to_phones.join(', ')}"
  rescue StandardError => e
    Rails.logger.error "KC FreePBX SMS Job: Failed to send article #{article_id}: #{e.message}"

    if executions >= 3
      begin
        article = Ticket::Article.find_by(id: article_id)
        if article
          article.preferences[PREFS_KEY] ||= {}
          article.preferences[PREFS_KEY][:delivery_status] = 'failed'
          article.preferences[PREFS_KEY][:delivery_error]  = e.message.truncate(500)
          article.save!
        end
      rescue StandardError => inner
        Rails.logger.error "KC FreePBX SMS Job: Failed to update delivery status: #{inner.message}"
      end
    end

    raise
  end

  private

  def plain_text(html)
    return '' if html.blank?

    text = html.gsub(%r{<br\s*/?>}i, "\n")
    text = text.gsub(%r{</(?:p|div|li|tr)>}i, "\n")
    text = ActionController::Base.helpers.strip_tags(text)
    text = text.gsub('&nbsp;', ' ')
    text = CGI.unescapeHTML(text)
    text = text.gsub(" ", ' ')
    text = text.gsub(/[^\S\n]+/, ' ')
    text.gsub(/\n{3,}/, "\n\n").strip
  end

  def find_our_phone(ticket)
    latest_customer_pref(ticket, :to_phone)
  end

  def find_channel_id(ticket)
    latest_customer_pref(ticket, :channel_id)
  end

  def latest_customer_pref(ticket, key)
    customer_sender = Ticket::Article::Sender.find_by(name: 'Customer')
    return nil if customer_sender.nil?

    ticket.articles.where(sender_id: customer_sender.id).order(created_at: :desc).each do |art|
      value = art.preferences&.dig(PREFS_KEY, key)
      return value if value.present?
    end
    nil
  end
end
