# KC: Polling job for RingCentral SMS messages.
#
# Runs every 60 seconds via Scheduler. Polls the RingCentral message store
# for inbound SMS/MMS messages since last poll. Acts as a fallback for
# missed webhook notifications.
#
# Safety:
#   - safe_constantize on KC classes
#   - Per-channel rescue so one broken channel doesn't stop the others
#   - Skips outbound messages
#   - Only processes messages created after last poll (or channel creation)
class Kc::PollRingcentralSmsMessagesJob < ApplicationJob

  def perform
    Channel.where(area: 'RingCentralSms::Account', active: true).find_each do |channel|
      poll_channel(channel)
    rescue => e
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
    rescue => e
      Rails.logger.error "KC RingCentral Poll: Token refresh failed for channel #{channel.id}: #{e.message}"
      return
    end

    # Determine poll window
    last_poll = opts[:last_poll_at]
    date_from = if last_poll.present?
                  last_poll.to_s
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
    rescue => e
      Rails.logger.error "KC RingCentral Poll: Message store query failed for channel #{channel.id}: #{e.message}"
      return
    end

    messages = result['records'] || result[:records] || []
    Rails.logger.info "KC RingCentral Poll: Found #{messages.size} messages for channel #{channel.id}" if messages.any?

    driver = Channel::Driver::KcRingcentralSms.new

    messages.each do |message|
      process_polled_message(driver, channel, message, opts)
    rescue => e
      msg_id = (message['id'] || message[:id]) rescue 'unknown'
      Rails.logger.error "KC RingCentral Poll: Failed to process message #{msg_id}: #{e.message}"
    end

    # Update last_poll_at timestamp
    channel.with_lock do
      channel.reload
      channel.options[:last_poll_at] = Time.current.utc.iso8601
      channel.save!
    end
  rescue => e
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

    # Build attachment list
    attachments = Array(message[:attachments]).map do |att|
      {
        id:           att[:id].to_s,
        content_type: att[:contentType] || att[:type] || 'application/octet-stream',
        filename:     att[:fileName] || "attachment_#{att[:id]}",
      }
    end.select { |a| a[:id].present? }

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

  def persist_tokens(channel, rc)
    channel.with_lock do
      channel.reload
      channel.options[:access_token]  = rc.access_token
      channel.options[:refresh_token] = rc.refresh_token
      channel.save!
    end
  rescue => e
    Rails.logger.error "KC RingCentral Poll: Failed to persist tokens: #{e.message}"
  end
end
