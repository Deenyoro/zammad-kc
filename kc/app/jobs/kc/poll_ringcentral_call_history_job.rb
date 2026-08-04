# KC: Polling job for RingCentral call history.
#
# Runs every 5 minutes via Scheduler. Polls the RingCentral call log
# for completed voice calls since the last poll and files each one as
# a CLOSED ticket with article type 'phone', backdated to the call's
# start time — so phone activity counts toward per-organization ticket
# reporting without creating agent work or notifications.
#
# Division of labor with the missed-call feature:
#   - Missed INBOUND calls are skipped here whenever
#     kc_ringcentral_sms_missed_call_ticket is enabled — that feature
#     creates OPEN tickets (and optional auto-reply SMS) for follow-up.
#   - Everything else (answered inbound, all outbound, voicemail) is
#     history: closed on arrival, no triggers, no notifications.
#
# Safety:
#   - Gated on the kc_ringcentral_call_history_ticket setting
#   - safe_constantize on KC classes
#   - Per-channel and per-record rescue so one failure doesn't stop the rest
#   - Dedup by RC session ID via Ticket::Article message_id
#     ('rc_call:<sessionId>'; also skips 'rc_missed_call:<sessionId>')
#   - Trigger/notification suppression via Transaction disable — history
#     tickets must never page Discord or email agents
#   - In-progress calls skipped; watermark lags 15 minutes so records
#     get re-seen once RingCentral finalizes them (dedup absorbs overlap)
#   - Page cap per run; call-log is a heavy-rate-limit RC endpoint, so
#     paging sleeps between requests
class Kc::PollRingcentralCallHistoryJob < ApplicationJob

  PAGE_LIMIT       = 10
  PAGE_SLEEP       = 7 # seconds; RC call-log endpoint is heavy-throttled
  FINALIZE_LAG     = 15.minutes
  DISPATCH_DISABLE = ['Transaction::Trigger', 'Transaction::Notification'].freeze

  def perform
    return unless Setting.get('kc_ringcentral_call_history_ticket') == true

    Channel.where(area: 'RingCentralSms::Account', active: true).find_each do |channel|
      poll_channel(channel)
    rescue StandardError => e
      Rails.logger.error "KC RingCentral Call History: Failed for channel #{channel.id}: #{e.message}"
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
      Rails.logger.error 'KC RingCentral Call History: RingcentralApi class not found'
      return
    end

    begin
      rc = rc_class.with_channel_tokens(channel)
    rescue StandardError => e
      Rails.logger.error "KC RingCentral Call History: Token refresh failed for channel #{channel.id}: #{e.message}"
      return
    end

    opts      = channel.options.with_indifferent_access
    date_from = opts[:last_call_history_poll_at].presence || 24.hours.ago.utc.iso8601
    skip_missed = Setting.get('kc_ringcentral_sms_missed_call_ticket') == true

    created = 0
    page    = 1
    loop do
      begin
        api_result = rc.get_call_log(date_from: date_from, per_page: 100, type: 'Voice', page: page)
      rescue StandardError => e
        Rails.logger.error "KC RingCentral Call History: Call log query failed for channel #{channel.id}: #{e.message}"
        break
      end

      records = api_result['records'] || api_result[:records] || []
      break if records.blank?

      records.each do |call_record|
        created += 1 if process_call(channel, call_record, skip_missed)
      rescue StandardError => e
        session_id = begin
                       (call_record['sessionId'] || call_record[:sessionId]).to_s
                     rescue StandardError
                       'unknown'
                     end
        Rails.logger.error "KC RingCentral Call History: Failed to process call #{session_id}: #{e.message}"
      end

      break if records.size < 100

      page += 1
      if page > PAGE_LIMIT
        Rails.logger.warn "KC RingCentral Call History: Page cap (#{PAGE_LIMIT}) hit for channel #{channel.id} — remainder picked up next run"
        break
      end
      sleep PAGE_SLEEP
    end

    Rails.logger.info "KC RingCentral Call History: Created #{created} call ticket(s) for channel #{channel.id}" if created.positive?

    # Watermark lags behind now so RingCentral has time to finalize
    # records; the overlap is absorbed by session-ID dedup.
    channel.with_lock do
      channel.reload
      channel.options[:last_call_history_poll_at] = FINALIZE_LAG.ago.utc.iso8601
      channel.save!
    end
  rescue StandardError => e
    Rails.logger.error "KC RingCentral Call History: Failed to update poll watermark for channel #{channel.id}: #{e.message}"
  end

  # Returns true when a ticket was created, false/nil when skipped.
  def process_call(channel, call_record, skip_missed)
    call_record = call_record.with_indifferent_access

    session_id = call_record[:sessionId].to_s
    return false if session_id.blank?

    result = call_record[:result].to_s
    return false if result.blank? || result == 'In Progress'

    inbound = call_record[:direction].to_s == 'Inbound'

    # Missed inbound calls belong to the missed-call feature (OPEN tickets)
    return false if inbound && result == 'Missed' && skip_missed

    # Dedup against both this job's tickets and missed-call tickets
    return false if Ticket::Article.where(message_id: ["rc_call:#{session_id}", "rc_missed_call:#{session_id}"]).exists?

    from_number = call_record.dig(:from, :phoneNumber)
    to_number   = call_record.dig(:to, :phoneNumber)
    external    = inbound ? from_number : to_number
    return false if external.blank? # internal extension-to-extension call

    rc_class = 'Kc::RingcentralApi'.safe_constantize
    e164     = rc_class ? rc_class.normalize_phone(external) : external
    from_e164 = rc_class && from_number.present? ? rc_class.normalize_phone(from_number) : from_number
    to_e164   = rc_class && to_number.present?   ? rc_class.normalize_phone(to_number)   : to_number

    start_time = begin
                   Time.zone.parse(call_record[:startTime].to_s)
                 rescue ArgumentError, TypeError
                   nil
                 end
    return false if start_time.nil?

    duration = call_record[:duration].to_i

    transaction_class = 'Transaction'.safe_constantize
    if transaction_class.nil?
      Rails.logger.error 'KC RingCentral Call History: Transaction class not found'
      return false
    end

    # disable: history tickets must never fire triggers (Discord) or
    # agent notifications — they are records, not work.
    transaction_class.execute(disable: DISPATCH_DISABLE, reset_user_id: true) do
      user       = find_or_create_user(e164)
      group      = Group.find_by(id: channel.group_id) || Group.first
      phone_type = Ticket::Article::Type.find_by(name: 'phone')
      closed     = Ticket::State.find_by(name: 'closed')
      sender     = Ticket::Article::Sender.find_by(name: inbound ? 'Customer' : 'Agent')

      ticket = Ticket.create!(
        title:                  "Phone call #{inbound ? 'from' : 'to'} #{e164}",
        group_id:               group.id,
        customer_id:            user.id,
        state_id:               closed&.id || Ticket::State.find_by(default_create: true)&.id,
        priority_id:            Ticket::Priority.find_by(default_create: true)&.id || Ticket::Priority.first&.id,
        create_article_type_id: phone_type&.id,
        preferences:            {
          ringcentral_call: {
            session_id: session_id,
            direction:  call_record[:direction],
            result:     result,
            duration:   duration,
            start_time: call_record[:startTime],
            from_phone: from_e164,
            to_phone:   to_e164,
          },
        },
        created_at:    start_time,
        updated_at:    start_time,
        close_at:      start_time + duration,
        created_by_id: inbound ? user.id : 1,
        updated_by_id: 1,
      )

      body = [
        "#{inbound ? 'Inbound' : 'Outbound'} call — #{result}",
        "#{from_e164 || call_record.dig(:from, :extensionNumber)} → #{to_e164 || call_record.dig(:to, :extensionNumber)}",
        "Time: #{start_time.in_time_zone.strftime('%Y-%m-%d %H:%M')}  Duration: #{format('%d:%02d', duration / 60, duration % 60)}",
      ].join("\n")

      Ticket::Article.create!(
        ticket_id:     ticket.id,
        type_id:       phone_type&.id,
        sender_id:     sender&.id,
        from:          e164,
        subject:       'Call record',
        body:          body,
        content_type:  'text/plain',
        message_id:    "rc_call:#{session_id}",
        internal:      false,
        created_at:    start_time,
        updated_at:    start_time,
        preferences:   {
          ringcentral_call: {
            session_id: session_id,
            channel_id: channel.id,
          },
        },
        created_by_id: inbound ? user.id : 1,
        updated_by_id: 1,
      )
    end

    true
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

end
