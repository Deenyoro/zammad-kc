# KC: Creates tickets and sends auto-reply texts for calls the team missed
# on FreePBX.
#
# RingCentral rings first; whatever it does not answer is forwarded to
# FreePBX, where the team's extensions ring. A call missed at that second
# layer is still a missed customer call, so it gets the same treatment as a
# missed RingCentral call: a ticket, and a text back to the caller.
#
# The text is sent through RingCentral, because RingCentral owns SMS for the
# whole system. Which number it comes from is configurable and may be any
# number in the system (Kc::OutboundSms).
class Kc::PollFreepbxMissedCallsJob < ApplicationJob

  # FreePBX writes a CDR row when the call ends, but a transfer can settle
  # slightly later; re-reading a small overlap is harmless because dedup is
  # keyed on the call's unique id.
  LOOKBACK_MINUTES = 60

  def perform
    return if !feature_enabled?

    Channel.where(area: 'Freepbx::Account', active: true).find_each do |channel|
      poll_channel(channel)
    rescue StandardError => e
      Rails.logger.error "KC FreePBX Missed Calls: Failed for channel #{channel.id}: #{e.message}"
    end
  end

  # Class method called by Scheduler
  def self.perform_now
    new.perform
  end

  private

  def feature_enabled?
    Setting.get('kc_freepbx_missed_call_ticket') == true ||
      Setting.get('kc_freepbx_missed_call_autoreply') == true
  end

  def poll_channel(channel)
    api_class = 'Kc::FreepbxApi'.safe_constantize
    if api_class.nil?
      Rails.logger.error 'KC FreePBX Missed Calls: FreepbxApi class not found'
      return
    end

    api  = api_class.for_channel(channel)
    opts = channel.options.with_indifferent_access

    begin
      calls = api.calls(
        since:         opts[:last_missed_call_poll_at],
        since_minutes: LOOKBACK_MINUTES,
        missed:        true,
        direction:     'inbound',
        limit:         200,
      )
      clear_connection_error(channel)
    rescue StandardError => e
      store_connection_error(channel, e.message)
      Rails.logger.error "KC FreePBX Missed Calls: Call query failed for channel #{channel.id}: #{e.message}"
      return
    end

    return if calls.blank?

    Rails.logger.info "KC FreePBX Missed Calls: Found #{calls.size} missed call(s) for channel #{channel.id}"

    # Advance only up to the last row we actually handled. A row that blows up
    # stops the watermark where it is, so the next run re-reads it instead of
    # silently dropping a missed call; dedup keeps the rows before it from
    # being handled twice.
    watermark = nil
    calls.each do |call|
      call = call.with_indifferent_access
      begin
        process_call(channel, call)
      rescue StandardError => e
        Rails.logger.error "KC FreePBX Missed Calls: Failed to process call #{call[:uniqueid]}: #{e.message}"
        break
      end
      watermark = call[:calldate] if call[:calldate].present?
    end

    return if watermark.blank?

    channel.with_lock do
      channel.reload
      channel.options[:last_missed_call_poll_at] = watermark
      channel.save!
    end
  rescue StandardError => e
    Rails.logger.error "KC FreePBX Missed Calls: Failed to update watermark for channel #{channel.id}: #{e.message}"
  end

  def process_call(channel, call)
    unique_id = call[:uniqueid].to_s
    return if unique_id.blank?

    caller = normalize(call[:src].presence || call[:cnum])
    return if caller.blank?

    # Ignore internal extension-to-extension calls; only real callers matter.
    return if caller.to_s.delete('+').length < 7

    dialed    = normalize(call[:did].presence || call[:dst])
    dedup_key = "freepbx_missed_call:#{unique_id}"
    return if already_processed?(channel, dedup_key, unique_id)

    create_ticket = Setting.get('kc_freepbx_missed_call_ticket') == true
    send_reply    = Setting.get('kc_freepbx_missed_call_autoreply') == true
    return if !create_ticket && !send_reply

    reply_from = Setting.get('kc_freepbx_missed_call_autoreply_from').to_s.presence

    # Claim the call before acting on it. The dedup key is a reservation, not
    # a receipt: if the ticket or the text fails halfway we would rather drop
    # this call — and say so in the log — than text the customer twice on the
    # next run.
    mark_processed(channel, unique_id)

    create_missed_call_ticket(channel, dedup_key, caller, dialed, call, reply_from) if create_ticket

    return if !send_reply

    message = Setting.get('kc_freepbx_missed_call_autoreply_message').to_s.presence ||
              'We are sorry for missing your call. A ticket has been created and our team will follow up with you shortly.'
    Kc::OutboundSms.deliver(to: caller, text: message, from: reply_from,
                            label: 'KC FreePBX Missed Calls')
  end

  def already_processed?(channel, dedup_key, unique_id)
    return true if Ticket::Article.exists?(message_id: dedup_key)

    processed = channel.options.with_indifferent_access[:processed_call_ids]
    return false if processed.blank?

    Array(processed).include?(unique_id)
  end

  def mark_processed(channel, unique_id)
    channel.with_lock do
      channel.reload
      ids = Array(channel.options[:processed_call_ids])
      ids << unique_id if ids.exclude?(unique_id)
      channel.options[:processed_call_ids] = ids.last(1000)
      channel.save!
    end
  rescue StandardError => e
    Rails.logger.error "KC FreePBX Missed Calls: Failed to mark call #{unique_id} processed: #{e.message}"
  end

  def create_missed_call_ticket(channel, dedup_key, caller, dialed, call, reply_from)
    transaction_class = 'Transaction'.safe_constantize
    if transaction_class.nil?
      Rails.logger.error 'KC FreePBX Missed Calls: Transaction class not found'
      return
    end

    # The ticket is answered by texting the caller back, and texting runs on
    # RingCentral — so the SMS preferences point at the RingCentral channel
    # that owns the reply number.
    sms_channel = Kc::OutboundSms.channel_for(reply_from)
    sms_from    = Kc::OutboundSms.normalize(reply_from).presence ||
                  (sms_channel && Kc::OutboundSms.normalize(sms_channel.options.with_indifferent_access[:phone_number]))

    transaction_class.execute(reset_user_id: true, context: 'freepbx_missed_call') do
      user  = find_or_create_user(caller)
      group = Group.find_by(id: channel.group_id) || Group.first

      title_template = Setting.get('kc_freepbx_missed_call_ticket_title').to_s.presence ||
                       'Missed call from {phone}'
      title = title_template.gsub('{phone}', caller.to_s).truncate(100, omission: '...')

      time_display = begin
                       Time.zone.parse(call[:calldate_utc].presence || call[:calldate].to_s)&.strftime('%Y-%m-%d %H:%M') ||
                         call[:calldate].to_s
                     rescue ArgumentError, TypeError
                       call[:calldate].to_s
                     end

      sms_article_type = Ticket::Article::Type.find_by(name: 'ringcentral_sms_message')

      preferences = {
        freepbx_missed_call: {
          from_phone: caller,
          to_phone:   dialed,
          call_time:  call[:calldate_utc].presence || call[:calldate],
          uniqueid:   call[:uniqueid],
          channel_id: channel.id,
        },
      }
      # Only advertise SMS reply when there is a number to reply from.
      if sms_channel && sms_from.present?
        preferences[:ringcentral_sms] = {
          from_phone: caller,
          to_phone:   sms_from,
          channel_id: sms_channel.id,
        }
      end

      ticket = Ticket.create!(
        title:                  title,
        group_id:               group.id,
        customer_id:            user.id,
        state_id:               Ticket::State.find_by(default_create: true)&.id || Ticket::State.find_by(name: 'new')&.id,
        priority_id:            Ticket::Priority.find_by(default_create: true)&.id || Ticket::Priority.first&.id,
        create_article_type_id: sms_article_type&.id,
        preferences:            preferences,
        updated_by_id:          user.id,
        created_by_id:          user.id,
      )

      article_type = Ticket::Article::Type.find_by(name: 'note') || Ticket::Article::Type.first
      sender       = Ticket::Article::Sender.find_by(name: 'Customer') || Ticket::Article::Sender.first

      body_lines = ["Missed call from #{caller} at #{time_display} (FreePBX)."]
      body_lines << "Number dialed: #{dialed}" if dialed.present? && dialed != caller
      body_lines << "Result: #{call[:disposition]}" if call[:disposition].present?

      Ticket::Article.create!(
        ticket_id:     ticket.id,
        type_id:       article_type&.id,
        sender_id:     sender&.id,
        from:          caller,
        subject:       'Missed Call',
        body:          body_lines.join("\n"),
        content_type:  'text/plain',
        message_id:    dedup_key,
        internal:      false,
        preferences:   preferences,
        updated_by_id: user.id,
        created_by_id: user.id,
      )

      Rails.logger.info "KC FreePBX Missed Calls: Created ticket #{ticket.id} for missed call from #{caller}"
    end
  end

  def find_or_create_user(phone)
    user = User.find_by(phone: phone) || User.find_by(mobile: phone)
    return user if user

    User.create!(
      firstname:     phone,
      lastname:      '',
      phone:         phone,
      active:        true,
      role_ids:      Role.signup_role_ids,
      updated_by_id: 1,
      created_by_id: 1,
    )
  end

  def normalize(number)
    Kc::OutboundSms.normalize(number)
  end

  def store_connection_error(channel, message)
    channel.with_lock do
      channel.reload
      channel.options[:last_connection_error]    = message.to_s.truncate(500)
      channel.options[:last_connection_error_at] = Time.current.utc.iso8601
      channel.status_in   = 'error'
      channel.last_log_in = message.to_s.truncate(500)
      channel.save!
    end
  rescue StandardError => e
    Rails.logger.error "KC FreePBX: Failed to store connection error: #{e.message}"
  end

  def clear_connection_error(channel)
    return if channel.options[:last_connection_error].blank? && channel.status_in != 'error'

    channel.with_lock do
      channel.reload
      channel.options.delete(:last_connection_error)
      channel.options.delete(:last_connection_error_at)
      channel.status_in   = 'ok'
      channel.last_log_in = nil
      channel.save!
    end
  rescue StandardError => e
    Rails.logger.error "KC FreePBX: Failed to clear connection error: #{e.message}"
  end
end
