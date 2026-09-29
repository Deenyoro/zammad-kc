# KC: Processes a text message the FreePBX connector pushed to the webhook.
#
# Called asynchronously from Kc::FreepbxSmsWebhookController after the
# token matched a connection. The payload is one connector message (see
# Kc::FreepbxApi), passed to the channel driver:
#   - inbound  → driver.process (customer article)
#   - outbound → driver.process_outbound (text sent from UCP / Sangoma
#                Connect; texts Zammad or the system sent are skipped)
#
# Safety:
#   - safe_constantize on KC classes
#   - Defensive nil checks on payload fields
class Kc::ProcessFreepbxSmsWebhookJob < ApplicationJob
  retry_on StandardError, wait: 10.seconds, attempts: 3

  def perform(channel_id:, message:)
    channel = Channel.find_by(id: channel_id, area: 'Freepbx::Account')
    if channel.nil?
      Rails.logger.warn "KC FreePBX SMS Webhook Job: Channel #{channel_id} not found"
      return
    end
    return if !channel.active?
    return if Setting.get('kc_freepbx_sms_enabled') != true

    poll_class = 'Kc::PollFreepbxSmsMessagesJob'.safe_constantize
    if poll_class.nil?
      Rails.logger.error 'KC FreePBX SMS Webhook Job: PollFreepbxSmsMessagesJob class not found'
      return
    end

    data   = poll_class.message_data_from_record(message, channel.options)
    driver = Channel::Driver::KcFreepbx.new

    if data[:direction] == 'outbound'
      driver.process_outbound(channel.options, data, channel) if data[:to_phones].any?
      return
    end

    if data[:from_phone].blank?
      Rails.logger.warn "KC FreePBX SMS Webhook Job: Missing from number in webhook for channel #{channel_id}"
      return
    end

    driver.process(channel.options, data, channel)
  end
end
