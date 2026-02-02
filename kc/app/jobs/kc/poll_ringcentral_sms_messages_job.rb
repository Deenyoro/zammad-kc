# KC: Polling job for RingCentral SMS messages.
#
# Runs every 60 seconds via Scheduler. Polls the RingCentral message store
# for SMS/MMS messages since last poll. Acts as a fallback for
# missed webhook notifications.
#
# Two-pass polling:
#   1. Inbound messages → creates customer-facing ticket articles
#   2. Outbound messages → captures replies sent from the RingCentral app
#      (not through Zammad) as internal notes for conversation context.
#      Zammad-sent outbound messages are skipped via dedup (their RC
#      message ID is already stored on the article by the communicate job).
#
# Safety:
#   - safe_constantize on KC classes
#   - Per-channel rescue so one broken channel doesn't stop the others
#   - Only processes messages created after last poll (or channel creation)
class Kc::PollRingcentralSmsMessagesJob < ApplicationJob

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

  private

  def poll_channel(channel)
    rc_class = 'Kc::RingcentralApi'.safe_constantize
    if rc_class.nil?
      Rails.logger.error 'KC RingCentral Poll: RingcentralApi class not found'
      return
    end

    opts = channel.options.with_indifferent_access
    rc = rc_class.new(
      client_id:     opts[:client_id],
      client_secret: opts[:client_secret],
      access_token:  opts[:access_token],
      refresh_token: opts[:refresh_token],
    )

    begin
      rc.refresh_access_token!
      persist_tokens(channel, rc)
    rescue StandardError => e
      Rails.logger.error "KC RingCentral Poll: Token refresh failed for channel #{channel.id}: #{e.message} — " \
                         'Polling skipped this cycle. Reauthenticate the channel in Admin > KC Extensions > RingCentral SMS if this persists.'
      return
    end

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

    begin
      result = rc.get_message_store(
        message_type: 'SMS',
        direction:    'Inbound',
        date_from:    date_from,
        per_page:     100,
      )
    rescue StandardError => e
      Rails.logger.error "KC RingCentral Poll: Message store query failed for channel #{channel.id}: #{e.message}"
      return
    end

    messages = result['records'] || result[:records] || []
    Rails.logger.info "KC RingCentral Poll: Found #{messages.size} messages for channel #{channel.id}" if messages.any?

    driver = Channel::Driver::KcRingcentralSms.new

    messages.each do |message|
      process_polled_message(driver, channel, message, opts)
    rescue StandardError => e
      msg_id = (message['id'] || message[:id]) rescue 'unknown' # rubocop:disable Style/RescueModifier
      Rails.logger.error "KC RingCentral Poll: Failed to process message #{msg_id}: #{e.message}"
    end

    # Pass 2: poll outbound messages for replies sent from the RC app
    poll_outbound_messages(driver, channel, rc, opts, date_from)

    # Update last_poll_at timestamp
    channel.with_lock do
      channel.reload
      channel.options[:last_poll_at] = Time.current.utc.iso8601
      channel.save!
    end
  rescue StandardError => e
    Rails.logger.error "KC RingCentral Poll: Failed to update last_poll_at for channel #{channel.id}: #{e.message}"
  end

  def process_polled_message(driver, channel, message, opts)
    message = message.with_indifferent_access

    # Skip non-SMS
    msg_type = message[:type].to_s
    return unless %w[SMS Pager].include?(msg_type)

    # Skip outbound
    return if message[:direction].to_s == 'Outbound'

    from_phone = message.dig(:from, :phoneNumber) || message.dig(:from, :extensionNumber)
    to_entries  = Array(message[:to])
    to_phone    = to_entries.first&.dig(:phoneNumber) || to_entries.first&.dig(:extensionNumber)

    return if from_phone.blank?

    # Build attachment list (skip "Text" type — that's the SMS body, not a real attachment)
    attachments = Array(message[:attachments]).filter_map do |att|
      next if att[:type].to_s == 'Text'
      next if att[:id].blank?

      content_type = att[:contentType] || 'application/octet-stream'
      filename = att[:fileName] || mms_filename(att[:id], content_type)

      {
        id:           att[:id].to_s,
        content_type: content_type,
        filename:     filename,
      }
    end

    message_data = {
      message_id:  message[:id].to_s,
      from_phone:  from_phone,
      to_phone:    to_phone || opts[:phone_number],
      text:        message[:subject] || '',
      direction:   message[:direction],
      created_at:  message[:creationTime] || message[:lastModifiedTime],
      attachments: attachments,
    }

    # process() handles dedup internally via message_id
    driver.process(channel.options, message_data, channel)
  end

  def poll_outbound_messages(driver, channel, rc, opts, date_from)
    begin
      result = rc.get_message_store(
        message_type: 'SMS',
        direction:    'Outbound',
        date_from:    date_from,
        per_page:     100,
      )
    rescue StandardError => e
      Rails.logger.error "KC RingCentral Poll: Outbound message store query failed for channel #{channel.id}: #{e.message}"
      return
    end

    messages = result['records'] || result[:records] || []
    return if messages.empty?

    Rails.logger.info "KC RingCentral Poll: Found #{messages.size} outbound messages for channel #{channel.id}"

    messages.each do |message|
      process_outbound_message(driver, channel, message, opts)
    rescue StandardError => e
      msg_id = (message['id'] || message[:id]) rescue 'unknown' # rubocop:disable Style/RescueModifier
      Rails.logger.error "KC RingCentral Poll: Failed to process outbound message #{msg_id}: #{e.message}"
    end
  end

  def process_outbound_message(driver, channel, message, opts)
    message = message.with_indifferent_access

    # Skip non-SMS
    msg_type = message[:type].to_s
    return unless %w[SMS Pager].include?(msg_type)

    # Only process outbound
    return unless message[:direction].to_s == 'Outbound'

    from_phone = message.dig(:from, :phoneNumber) || message.dig(:from, :extensionNumber)
    to_entries  = Array(message[:to])
    to_phone    = to_entries.first&.dig(:phoneNumber) || to_entries.first&.dig(:extensionNumber)

    return if to_phone.blank?

    message_data = {
      message_id: message[:id].to_s,
      from_phone: from_phone || opts[:phone_number],
      to_phone:   to_phone,
      text:       message[:subject] || '',
      direction:  message[:direction],
      created_at: message[:creationTime] || message[:lastModifiedTime],
    }

    driver.process_outbound(channel.options, message_data, channel)
  end

  def persist_tokens(channel, rc)
    channel.with_lock do
      channel.reload
      channel.options[:access_token]  = rc.access_token
      channel.options[:refresh_token] = rc.refresh_token
      channel.save!
    end
  rescue StandardError => e
    Rails.logger.error "KC RingCentral Poll: Failed to persist tokens: #{e.message}"
  end

  # Generate a filename with proper extension from content type.
  # RingCentral MMS attachments have no fileName field.
  def mms_filename(attachment_id, content_type)
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
end
