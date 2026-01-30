# KC: Polling job for RingCentral missed calls.
#
# Runs every 60 seconds via Scheduler. Polls the RingCentral call log
# for inbound calls with result "Missed" since last poll.
#
# When enabled via settings:
#   - Creates a ticket for each missed call (kc_ringcentral_sms_missed_call_ticket)
#   - Sends an auto-reply SMS to the caller (kc_ringcentral_sms_missed_call_autoreply)
#
# Safety:
#   - safe_constantize on KC classes
#   - Per-channel rescue so one broken channel doesn't stop the others
#   - Deduplicates by call session ID (via Ticket::Article message_id when
#     ticket creation is on, or via channel.options[:processed_missed_call_ids]
#     when only auto-reply is enabled)
#   - Client-side result=Missed filtering as defense-in-depth
#     (the API query param may be silently ignored by some RC endpoints)
#   - Checks settings before creating tickets or sending SMS
class Kc::PollRingcentralMissedCallsJob < ApplicationJob

  def perform
    return unless feature_enabled?

    Channel.where(area: 'RingCentralSms::Account', active: true).find_each do |channel|
      poll_channel(channel)
    rescue StandardError => e
      Rails.logger.error "KC RingCentral Missed Calls: Failed for channel #{channel.id}: #{e.message}"
    end
  end

  # Class method called by Scheduler
  def self.perform_now
    new.perform
  end

  private

  def feature_enabled?
    Setting.get('kc_ringcentral_sms_missed_call_ticket') == true ||
      Setting.get('kc_ringcentral_sms_missed_call_autoreply') == true
  end

  def poll_channel(channel)
    rc_class = 'Kc::RingcentralApi'.safe_constantize
    if rc_class.nil?
      Rails.logger.error 'KC RingCentral Missed Calls: RingcentralApi class not found'
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
      Rails.logger.error "KC RingCentral Missed Calls: Token refresh failed for channel #{channel.id}: #{e.message}"
      return
    end

    # Determine poll window
    last_poll = opts[:last_missed_call_poll_at]
    date_from = if last_poll.present?
                  last_poll.to_s
                else
                  channel.created_at.utc.iso8601
                end

    begin
      api_result = rc.get_call_log(
        direction: 'Inbound',
        result:    'Missed',
        date_from: date_from,
        per_page:  100,
        type:      'Voice',
      )
    rescue StandardError => e
      Rails.logger.error "KC RingCentral Missed Calls: Call log query failed for channel #{channel.id}: #{e.message}"
      return
    end

    records = api_result['records'] || api_result[:records] || []

    # Defense-in-depth: filter client-side in case the API ignores
    # the result=Missed query parameter on certain RC plan tiers.
    records = records.select do |r|
      r = r.with_indifferent_access
      r[:direction].to_s == 'Inbound' && r[:result].to_s == 'Missed'
    end

    Rails.logger.info "KC RingCentral Missed Calls: Found #{records.size} missed calls for channel #{channel.id}" if records.any?

    records.each do |call_record|
      process_missed_call(channel, call_record, rc, opts)
    rescue StandardError => e
      session_id = begin
                     (call_record['sessionId'] || call_record[:sessionId]).to_s
                   rescue StandardError
                     'unknown'
                   end
      Rails.logger.error "KC RingCentral Missed Calls: Failed to process call #{session_id}: #{e.message}"
    end

    # Update last poll timestamp
    channel.with_lock do
      channel.reload
      channel.options[:last_missed_call_poll_at] = Time.current.utc.iso8601
      channel.save!
    end
  rescue StandardError => e
    Rails.logger.error "KC RingCentral Missed Calls: Failed to update poll timestamp for channel #{channel.id}: #{e.message}"
  end

  def process_missed_call(channel, call_record, rc, opts)
    call_record = call_record.with_indifferent_access

    session_id = call_record[:sessionId].to_s
    return if session_id.blank?

    from_info  = call_record[:from] || {}
    from_phone = from_info[:phoneNumber] || from_info[:extensionNumber]
    return if from_phone.blank?

    to_info  = call_record[:to] || {}
    to_phone = to_info[:phoneNumber] || to_info[:extensionNumber] || opts[:phone_number]

    start_time = call_record[:startTime]

    # Dedup: skip if we already processed this call session
    dedup_key = "rc_missed_call:#{session_id}"
    return if already_processed?(channel, dedup_key, session_id)

    create_ticket = Setting.get('kc_ringcentral_sms_missed_call_ticket') == true
    send_reply    = Setting.get('kc_ringcentral_sms_missed_call_autoreply') == true

    return unless create_ticket || send_reply

    rc_class = 'Kc::RingcentralApi'.safe_constantize
    normalized_from = rc_class ? rc_class.normalize_phone(from_phone) : from_phone
    normalized_to   = rc_class ? rc_class.normalize_phone(to_phone)   : to_phone

    if create_ticket
      create_missed_call_ticket(channel, dedup_key, normalized_from, normalized_to, start_time)
    end

    if send_reply && normalized_from.present?
      send_autoreply_sms(rc, opts, normalized_from)
    end

    # Track this session ID as processed (for auto-reply-only dedup)
    mark_processed(channel, session_id)
  end

  # Checks both Ticket::Article message_id (for ticket-mode dedup) and
  # channel options (for auto-reply-only dedup) to avoid double-processing.
  def already_processed?(channel, dedup_key, session_id)
    return true if Ticket::Article.exists?(message_id: dedup_key)

    processed_ids = channel.options.with_indifferent_access[:processed_missed_call_ids]
    return false if processed_ids.blank?

    Array(processed_ids).include?(session_id)
  end

  # Stores the session ID in channel options so auto-reply-only mode
  # can dedup without creating tickets. Keeps only the last 200 IDs
  # to prevent unbounded growth.
  def mark_processed(channel, session_id)
    channel.with_lock do
      channel.reload
      ids = Array(channel.options[:processed_missed_call_ids])
      ids << session_id unless ids.include?(session_id)
      # Keep only the most recent 200 to bound storage
      channel.options[:processed_missed_call_ids] = ids.last(200)
      channel.save!
    end
  rescue StandardError => e
    Rails.logger.error "KC RingCentral Missed Calls: Failed to mark session #{session_id} as processed: #{e.message}"
  end

  def create_missed_call_ticket(channel, dedup_key, from_phone, to_phone, start_time)
    transaction_class = 'Transaction'.safe_constantize
    if transaction_class.nil?
      Rails.logger.error 'KC RingCentral Missed Calls: Transaction class not found'
      return
    end

    transaction_class.execute(reset_user_id: true, context: 'ringcentral_missed_call') do
      user = find_or_create_user(from_phone)
      group = Group.find_by(id: channel.group_id) || Group.first

      title_template = Setting.get('kc_ringcentral_sms_missed_call_ticket_title').to_s.presence || 'Missed call from {phone}'
      title = title_template.gsub('{phone}', from_phone.to_s).truncate(100, omission: '...')

      time_display = begin
                       Time.parse(start_time.to_s).in_time_zone.strftime('%Y-%m-%d %H:%M')
                     rescue ArgumentError, TypeError
                       start_time.to_s
                     end

      ticket = Ticket.create!(
        title:         title,
        group_id:      group.id,
        customer_id:   user.id,
        state_id:      Ticket::State.find_by(default_create: true)&.id || Ticket::State.find_by(name: 'new')&.id,
        priority_id:   Ticket::Priority.find_by(default_create: true)&.id || Ticket::Priority.first&.id,
        preferences:   {
          ringcentral_missed_call: {
            from_phone: from_phone,
            to_phone:   to_phone,
            call_time:  start_time,
          },
        },
        updated_by_id: user.id,
        created_by_id: user.id,
      )

      article_type = Ticket::Article::Type.find_by(name: 'note')
      sender       = Ticket::Article::Sender.find_by(name: 'Customer')

      body_lines = ["Missed call from #{from_phone} at #{time_display}."]
      body_lines << "Number dialed: #{to_phone}" if to_phone.present? && to_phone != from_phone

      Ticket::Article.create!(
        ticket_id:     ticket.id,
        type_id:       article_type&.id,
        sender_id:     sender&.id,
        from:          from_phone,
        subject:       'Missed Call',
        body:          body_lines.join("\n"),
        content_type:  'text/plain',
        message_id:    dedup_key,
        internal:      false,
        preferences:   {
          ringcentral_missed_call: {
            from_phone: from_phone,
            to_phone:   to_phone,
            channel_id: channel.id,
          },
        },
        updated_by_id: user.id,
        created_by_id: user.id,
      )

      Rails.logger.info "KC RingCentral Missed Calls: Created ticket #{ticket.id} for missed call from #{from_phone}"
    end
  end

  def send_autoreply_sms(rc, opts, to_phone)
    from_phone = opts[:phone_number]
    return if from_phone.blank?

    message = Setting.get('kc_ringcentral_sms_missed_call_autoreply_message').to_s.presence ||
              'We are sorry for missing your call. A ticket has been created and our team will follow up with you shortly.'

    begin
      rc.send_sms(from: from_phone, to: to_phone, text: message)
      Rails.logger.info "KC RingCentral Missed Calls: Sent auto-reply SMS to #{to_phone}"
    rescue StandardError => e
      Rails.logger.error "KC RingCentral Missed Calls: Failed to send auto-reply to #{to_phone}: #{e.message}"
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

  def persist_tokens(channel, rc)
    channel.with_lock do
      channel.reload
      channel.options[:access_token]  = rc.access_token
      channel.options[:refresh_token] = rc.refresh_token
      channel.save!
    end
  rescue StandardError => e
    Rails.logger.error "KC RingCentral Missed Calls: Failed to persist tokens: #{e.message}"
  end
end
