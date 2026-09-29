# KC: Polling job for FreePBX text messages.
#
# Runs every 60 seconds via Scheduler while kc_freepbx_sms_enabled is on.
# Reads new messages from the KC PBX connector (which fronts the PBX's SMS
# module) and hands them to the channel driver. The connector's webhook
# delivers texts instantly; this poll is the backup that catches anything
# the webhook missed.
#
# Two passes, like the RingCentral poll:
#   1. Inbound messages → customer-facing ticket articles
#   2. Outbound messages → texts sent from UCP / Sangoma Connect (not
#      through Zammad) captured as internal notes on the conversation's
#      ticket. Zammad-sent and system-sent texts are skipped (driver).
#
# The list of numbers the PBX can text from is refreshed on every run and
# cached on the channel for the admin page and the new-conversation pickers.
#
# Safety:
#   - safe_constantize on KC classes
#   - Per-channel rescue so one broken connection doesn't stop the others
#   - Watermark taken before the read so a text that lands mid-poll is
#     re-read next cycle (message-id dedup absorbs the overlap)
class Kc::PollFreepbxSmsMessagesJob < ApplicationJob
  include Kc::FreepbxChannelStatus

  PER_REQUEST = 500
  # A connection that never polled starts here rather than replaying the
  # PBX's whole message history as tickets.
  FIRST_POLL_LOOKBACK = 1.hour

  def perform
    return if Setting.get('kc_freepbx_sms_enabled') != true

    Channel.where(area: 'Freepbx::Account', active: true).find_each do |channel|
      poll_channel(channel)
    rescue StandardError => e
      Rails.logger.error "KC FreePBX SMS Poll: Failed for channel #{channel.id}: #{e.message}"
    end
  end

  # Class method called by Scheduler
  def self.perform_now
    new.perform
  end

  # Turns a connector message into the driver's message_data. Shared with
  # the webhook and backfill jobs so every path sees the same shape.
  def self.message_data_from_record(message, channel_options = {})
    message = message.with_indifferent_access
    opts    = (channel_options || {}).with_indifferent_access

    to_phones   = Array(message[:to]).map(&:to_s).compact_blank
    attachments = Array(message[:media]).filter_map do |media|
      media = media.with_indifferent_access
      next if media[:id].blank? && media[:url].blank?

      {
        id:           media[:id].to_s.presence,
        url:          media[:url].to_s.presence,
        content_type: media[:content_type].presence || 'application/octet-stream',
        filename:     media[:filename].presence,
      }
    end

    {
      message_id:  message[:id].to_s,
      from_phone:  message[:from].to_s.presence || opts[:sms_default_number],
      to_phone:    to_phones.first || opts[:sms_default_number],
      to_phones:   to_phones,
      text:        message[:text].to_s,
      direction:   message[:direction].to_s.downcase,
      created_at:  message[:created_at] || message[:time],
      extension:   message[:extension].to_s.presence,
      attachments: attachments,
    }
  end

  # Refreshes the cached list of texting numbers. Returns the list.
  def self.refresh_sms_numbers(channel, api = nil)
    api_class = 'Kc::FreepbxApi'.safe_constantize
    return [] if api_class.nil?

    api   ||= api_class.for_channel(channel)
    numbers = api.sms_numbers.map(&:with_indifferent_access).filter_map do |entry|
      number = Kc::OutboundSms.normalize(entry[:number])
      next if number.blank?

      { number: number, label: entry[:label].to_s.presence, extension: entry[:extension].to_s.presence }.compact
    end

    channel.with_lock do
      channel.reload
      channel.options[:sms_numbers]            = numbers
      channel.options[:sms_numbers_updated_at] = Time.current.utc.iso8601
      channel.save!
    end
    numbers
  rescue StandardError => e
    Rails.logger.warn "KC FreePBX SMS: could not refresh texting numbers for channel #{channel.id}: #{e.message}"
    Array(channel.options.with_indifferent_access[:sms_numbers])
  end

  private

  def poll_channel(channel)
    api_class = 'Kc::FreepbxApi'.safe_constantize
    if api_class.nil?
      Rails.logger.error 'KC FreePBX SMS Poll: FreepbxApi class not found'
      return
    end

    api  = api_class.for_channel(channel)
    opts = channel.options.with_indifferent_access

    since = opts[:last_sms_poll_at].presence || FIRST_POLL_LOOKBACK.ago.utc.iso8601
    poll_started_at = Time.current.utc

    begin
      messages = api.sms_messages(since: since, limit: PER_REQUEST)
      clear_freepbx_error(channel)
    rescue StandardError => e
      store_freepbx_error(channel, e.message)
      Rails.logger.error "KC FreePBX SMS Poll: message query failed for channel #{channel.id}: #{e.message}"
      return
    end

    self.class.refresh_sms_numbers(channel, api)

    messages = messages.map(&:with_indifferent_access).sort_by { |m| (m[:created_at] || m[:time] || m[:id]).to_s }
    Rails.logger.info "KC FreePBX SMS Poll: Found #{messages.size} message(s) for channel #{channel.id}" if messages.any?

    driver = Channel::Driver::KcFreepbx.new
    messages.each do |message|
      data = self.class.message_data_from_record(message, opts)
      if data[:direction] == 'outbound'
        driver.process_outbound(channel.options, data, channel) if data[:to_phones].any?
      elsif data[:from_phone].present?
        driver.process(channel.options, data, channel)
      end
    rescue StandardError => e
      Rails.logger.error "KC FreePBX SMS Poll: Failed to process message #{message[:id]}: #{e.message}"
    end

    channel.with_lock do
      channel.reload
      channel.options[:last_sms_poll_at] = poll_started_at.iso8601
      channel.save!
    end
  rescue StandardError => e
    Rails.logger.error "KC FreePBX SMS Poll: Failed to update watermark for channel #{channel.id}: #{e.message}"
  end
end
