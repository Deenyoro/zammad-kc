# KC: Polling job for RingCentral SMS messages.
#
# Runs every 60 seconds via Scheduler. Polls the RingCentral message store
# for SMS/MMS messages since last poll. Acts as a fallback for
# missed webhook notifications.
#
# Two-pass polling:
#   1. Inbound messages → creates customer-facing ticket articles
#   2. Outbound messages → captures texts sent from the RingCentral app
#      (not through Zammad) as internal notes on the conversation's ticket,
#      creating the ticket when the agent started the conversation.
#      Zammad-sent and system-sent texts are skipped (see the driver).
#
# Safety:
#   - safe_constantize on KC classes
#   - Per-channel rescue so one broken channel doesn't stop the others
#   - Only processes messages created after last poll (or channel creation)
#   - Pages through the store when a window holds more than one page
class Kc::PollRingcentralSmsMessagesJob < ApplicationJob
  include Kc::RingcentralAuthRecovery

  PER_PAGE  = 100
  MAX_PAGES = 10

  def perform
    Channel.where(area: 'RingCentralSms::Account', active: true).find_each do |channel|
      poll_channel(channel)
    rescue StandardError => e
      Rails.logger.error "KC RingCentral Poll: Failed for channel #{channel.id}: #{e.message}"
    end
  end

  # Class method called by Scheduler
  def self.perform_now
    new.perform
  end

  # Turns a RingCentral message-store record into the driver's message_data.
  # Shared with the webhook and backfill jobs so every path sees the same shape.
  def self.message_data_from_record(message, channel_options = {})
    message = message.with_indifferent_access
    opts    = (channel_options || {}).with_indifferent_access

    from_phone = message.dig(:from, :phoneNumber) || message.dig(:from, :extensionNumber)
    to_phones  = Array(message[:to]).filter_map { |t| t[:phoneNumber] || t[:extensionNumber] }

    # Skip "Text" type — that's the SMS body, not a real attachment
    attachments = Array(message[:attachments]).filter_map do |att|
      next if att[:type].to_s == 'Text'
      next if att[:id].blank?

      content_type = att[:contentType] || 'application/octet-stream'
      {
        id:           att[:id].to_s,
        content_type: content_type,
        filename:     att[:fileName] || mms_filename(att[:id], content_type),
      }
    end

    {
      message_id:  message[:id].to_s,
      from_phone:  from_phone.presence || opts[:phone_number],
      to_phone:    to_phones.first || opts[:phone_number],
      to_phones:   to_phones,
      text:        message[:subject] || '',
      direction:   message[:direction],
      created_at:  message[:creationTime] || message[:lastModifiedTime],
      attachments: attachments,
    }
  end

  # Generate a filename with proper extension from content type.
  # RingCentral MMS attachments have no fileName field.
  def self.mms_filename(attachment_id, content_type)
    ext = case content_type.to_s.downcase
          when 'image/jpeg', 'image/jpg' then '.jpg'
          when 'image/png'               then '.png'
          when 'image/gif'               then '.gif'
          when 'image/webp'              then '.webp'
          when 'image/heic'              then '.heic'
          when 'video/mp4'               then '.mp4'
          when 'video/3gpp'              then '.3gp'
          when 'audio/mpeg'              then '.mp3'
          when 'audio/ogg'               then '.ogg'
          when 'application/pdf'         then '.pdf'
          when %r{^image/}              then ".#{content_type.split('/').last}"
          when %r{^video/}              then ".#{content_type.split('/').last}"
          when %r{^audio/}              then ".#{content_type.split('/').last}"
          else                               ''
          end
    "mms_#{attachment_id}#{ext}"
  end

  private

  def poll_channel(channel)
    rc_class = 'Kc::RingcentralApi'.safe_constantize
    if rc_class.nil?
      Rails.logger.error 'KC RingCentral Poll: RingcentralApi class not found'
      return
    end

    begin
      rc = rc_class.with_channel_tokens(channel)
    rescue StandardError => e
      rc_record_auth_failure(channel, 'KC RingCentral Poll', e.message)
      return
    end

    opts = channel.options.with_indifferent_access

    # Determine poll window
    # Use last_poll_at if available. On first poll, use poll_cutoff_date if
    # configured (to avoid importing messages from before the addon was deployed).
    # If neither is set, use channel creation time (full backfill).
    last_poll = opts[:last_poll_at]
    cutoff_date = opts[:poll_cutoff_date]

    date_from = if last_poll.present?
                  last_poll.to_s
                elsif cutoff_date.present?
                  cutoff_date.to_s
                else
                  channel.created_at.utc.iso8601
                end

    # The watermark is taken before the queries so a text that lands while we
    # are reading is re-read next cycle (message-ID dedup absorbs the overlap)
    # instead of falling into the gap between query and save.
    poll_started_at = Time.current.utc

    messages = fetch_messages(channel, rc, 'Inbound', date_from)
    return if messages.nil?

    # The token worked — drop any stale auth banner from a previous failure.
    clear_auth_error(channel) if channel.options[:last_auth_error].present?

    Rails.logger.info "KC RingCentral Poll: Found #{messages.size} messages for channel #{channel.id}" if messages.any?

    driver = Channel::Driver::KcRingcentralSms.new

    messages.each do |message|
      process_polled_message(driver, channel, message, opts)
    rescue StandardError => e
      msg_id = (message['id'] || message[:id]) rescue 'unknown' # rubocop:disable Style/RescueModifier
      Rails.logger.error "KC RingCentral Poll: Failed to process message #{msg_id}: #{e.message}"
    end

    # Pass 2: poll outbound messages for texts sent from the RC app.
    # If this pass failed, leave the watermark where it is so the window is
    # re-read next cycle instead of silently dropping every agent text sent
    # from the RC app meanwhile.
    if !poll_outbound_messages(driver, channel, rc, opts, date_from)
      Rails.logger.warn "KC RingCentral Poll: Outbound pass failed for channel #{channel.id} — watermark not advanced"
      return
    end

    # Update last_poll_at timestamp
    channel.with_lock do
      channel.reload
      channel.options[:last_poll_at] = poll_started_at.iso8601
      channel.save!
    end
  rescue StandardError => e
    Rails.logger.error "KC RingCentral Poll: Failed to update last_poll_at for channel #{channel.id}: #{e.message}"
  end

  # Reads every page of the store for the direction/window. Returns nil when
  # the query failed (caller keeps the watermark), otherwise an array of
  # records oldest-first so articles are created in conversation order.
  def fetch_messages(channel, rc, direction, date_from)
    records = []
    page    = 1
    loop do
      result, _client = rc_call_with_auth_recovery(channel, 'KC RingCentral Poll', client: rc) do |client|
        client.get_message_store(
          message_type: 'SMS',
          direction:    direction,
          date_from:    date_from,
          per_page:     PER_PAGE,
          page:         page,
        )
      end
      return nil if result.nil?

      batch = result['records'] || result[:records] || []
      records.concat(batch)
      break if batch.size < PER_PAGE || page >= MAX_PAGES

      page += 1
    end
    records.sort_by { |m| (m['creationTime'] || m[:creationTime] || m['id']).to_s }
  rescue StandardError => e
    Rails.logger.error "KC RingCentral Poll: #{direction} message store query failed for channel #{channel.id}: #{e.message}"
    nil
  end

  def process_polled_message(driver, channel, message, opts)
    message = message.with_indifferent_access

    # Skip non-SMS
    msg_type = message[:type].to_s
    return unless %w[SMS Pager].include?(msg_type)

    # Skip outbound
    return if message[:direction].to_s == 'Outbound'

    message_data = self.class.message_data_from_record(message, opts)
    return if message_data[:from_phone].blank?

    # process() handles dedup internally via message_id
    driver.process(channel.options, message_data, channel)
  end

  # Returns true when the outbound window was read successfully.
  def poll_outbound_messages(driver, channel, rc, opts, date_from)
    messages = fetch_messages(channel, rc, 'Outbound', date_from)
    return false if messages.nil?
    return true if messages.empty?

    Rails.logger.info "KC RingCentral Poll: Found #{messages.size} outbound messages for channel #{channel.id}"

    messages.each do |message|
      process_outbound_message(driver, channel, message, opts)
    rescue StandardError => e
      msg_id = (message['id'] || message[:id]) rescue 'unknown' # rubocop:disable Style/RescueModifier
      Rails.logger.error "KC RingCentral Poll: Failed to process outbound message #{msg_id}: #{e.message}"
    end
    true
  end

  def process_outbound_message(driver, channel, message, opts)
    message = message.with_indifferent_access

    # Skip non-SMS
    msg_type = message[:type].to_s
    return unless %w[SMS Pager].include?(msg_type)

    # Only process outbound
    return unless message[:direction].to_s == 'Outbound'

    message_data = self.class.message_data_from_record(message, opts)
    return if message_data[:to_phones].empty?

    driver.process_outbound(channel.options, message_data, channel)
  end
end
