# KC: Processes a RingCentral SMS webhook notification.
#
# Called asynchronously from the webhook controller after validation.
# The instant-message event carries the message metadata, which is passed
# to the channel driver:
#   - Inbound  → driver.process (customer article)
#   - Outbound → driver.process_outbound (text sent from the RC app; texts
#                Zammad or the system sent are recognised and skipped)
#
# Safety:
#   - safe_constantize on KC classes
#   - Defensive nil checks on API response fields
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

    # Skip non-SMS message types
    msg_type = message_body[:type].to_s
    return unless %w[SMS Pager].include?(msg_type)

    poll_class = 'Kc::PollRingcentralSmsMessagesJob'.safe_constantize
    if poll_class.nil?
      Rails.logger.error 'KC RingCentral SMS Job: PollRingcentralSmsMessagesJob class not found'
      return
    end

    message_data = poll_class.message_data_from_record(message_body, channel.options)
    driver       = Channel::Driver::KcRingcentralSms.new

    if message_data[:direction].to_s == 'Outbound'
      return if message_data[:to_phones].empty?

      driver.process_outbound(channel.options, message_data, channel)
      return
    end

    if message_data[:from_phone].blank?
      Rails.logger.warn "KC RingCentral SMS Job: Missing from phone in webhook for channel #{channel_id}"
      return
    end

    # Process through channel driver (3-arg Zammad convention)
    driver.process(channel.options, message_data, channel)
  end
end
