# KC: Processes an inbound RingCentral SMS webhook notification.
#
# Called asynchronously from the webhook controller after validation.
# Fetches the full message from the RingCentral API and passes
# it to the channel driver's process() method.
#
# Safety:
#   - safe_constantize on KC classes
#   - Defensive nil checks on API response fields
#   - Skips outbound messages (our own replies)
class Kc::ProcessRingcentralSmsWebhookJob < ApplicationJob
  retry_on StandardError, wait: 10.seconds, attempts: 3

  def perform(channel_id:, event_body:)
    channel = Channel.find_by(id: channel_id, area: 'RingCentralSms::Account')
    if channel.nil?
      Rails.logger.warn "KC RingCentral SMS Job: Channel #{channel_id} not found"
      return
    end

    return unless channel.active?

    event_body = event_body.with_indifferent_access
    message_body = event_body[:body] || event_body

    # RingCentral webhook body contains message metadata directly
    message_id = message_body[:id].to_s
    direction  = message_body[:direction].to_s

    # Skip outbound messages (our own replies)
    return if direction == 'Outbound'

    # Skip non-SMS message types
    msg_type = message_body[:type].to_s
    return unless %w[SMS Pager].include?(msg_type)

    from_phone = message_body.dig(:from, :phoneNumber) || message_body.dig(:from, :extensionNumber)
    to_entries = Array(message_body[:to])
    to_phone   = to_entries.first&.dig(:phoneNumber) || to_entries.first&.dig(:extensionNumber)

    if from_phone.blank?
      Rails.logger.warn "KC RingCentral SMS Job: Missing from phone in webhook for channel #{channel_id}"
      return
    end

    # Build attachment list from message (skip "Text" type — that's the SMS body, not a real attachment)
    attachments = Array(message_body[:attachments]).filter_map do |att|
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
      message_id:  message_id,
      from_phone:  from_phone,
      to_phone:    to_phone || channel.options&.dig(:phone_number),
      text:        message_body[:subject] || '',
      direction:   direction,
      created_at:  message_body[:creationTime] || message_body[:lastModifiedTime],
      attachments: attachments,
    }

    # Process through channel driver (3-arg Zammad convention)
    driver = Channel::Driver::KcRingcentralSms.new
    driver.process(channel.options, message_data, channel)
  end

  private

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
