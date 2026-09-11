# KC: Polling job for RingCentral call history.
#
# Runs every 5 minutes via Scheduler. Polls the RingCentral call log for
# completed voice calls and files each one as a CLOSED ticket with article
# type 'phone', backdated to the call's start time — so phone activity
# counts toward per-organization ticket reporting without creating agent
# work or notifications.
#
# Division of labor with the missed-call feature:
#   - Missed INBOUND calls are skipped here whenever
#     kc_ringcentral_sms_missed_call_ticket is enabled — that feature
#     creates OPEN tickets (and optional auto-reply SMS) for follow-up.
#   - Everything else (answered inbound, all outbound, voicemail) is
#     history: closed on arrival, no triggers, no notifications.
#
# What RingCentral's log actually looks like, and why the job is shaped
# the way it is:
#   - A call to the main company number reaches this extension through
#     the IVR. While the call is live, and for a short while after, the
#     log shows a PRELIMINARY record for the session: direction Outbound,
#     from the customer, to the company number, a few seconds long. It is
#     later replaced by the real Inbound record with the same sessionId.
#     Filing the preliminary record produced "outbound" calls to our own
#     number, attributed to whichever user had that number on file.
#     So: records younger than SETTLE_LAG are not filed yet, records whose
#     external party is one of our own numbers are never filed, and a
#     record that changes after filing updates its ticket (upsert).
#   - A forwarded call (RingCentral → FreePBX) shows a FindMe leg to the
#     PBX number. RingCentral marks short PBX-answered calls "Missed". The
#     PBX's own records say which extension answered, so the ticket says
#     "Answered on FreePBX by ext 201 (Dean)" instead.
#
# Safety:
#   - Gated on the kc_ringcentral_call_history_ticket setting
#   - Per-channel and per-record rescue so one failure doesn't stop the rest
#   - Dedup by RC session ID via Ticket::Article message_id
#     ('rc_call:<sessionId>'; also skips 'rc_missed_call:<sessionId>')
#   - Trigger/notification suppression via Transaction disable
#   - The watermark never passes a record that was held back (in progress
#     or too young), so a long call is not lost while it is still running
#   - Page cap per run; call-log is a heavy-rate-limit RC endpoint
class Kc::PollRingcentralCallHistoryJob < ApplicationJob
  include Kc::RingcentralAuthRecovery
  include Kc::CallHistoryFiling

  PAGE_LIMIT   = 10
  PAGE_SLEEP   = 7 # seconds; RC call-log endpoint is heavy-throttled
  FINALIZE_LAG = 15.minutes # how far behind now the watermark sits
  SETTLE_LAG   = 8.minutes  # records younger than this are re-read later
  HOLD_LIMIT   = 24.hours   # a record stuck "In Progress" cannot pin the watermark forever

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

  # Re-reads a date range and files or corrects every call in it. Used to
  # repair tickets filed from preliminary records. Returns counts.
  def self.resync(from:, to: Time.current, channel: nil)
    new.resync(from: from, to: to, channel: channel)
  end

  def resync(from:, to: Time.current, channel: nil)
    channel ||= Channel.where(area: 'RingCentralSms::Account', active: true).order(:id).first
    raise 'no active RingCentral channel' if channel.nil?

    rc = 'Kc::RingcentralApi'.safe_constantize.with_channel_tokens(channel)
    skip_missed = Setting.get('kc_ringcentral_sms_missed_call_ticket') == true
    counts = Hash.new(0)
    page = 1
    loop do
      api_result, rc = rc_call_with_auth_recovery(channel, 'KC RingCentral Call History', client: rc) do |client|
        client.get_call_log(date_from: from.utc.iso8601, date_to: to.utc.iso8601, per_page: 100, type: 'Voice', page: page, view: 'Detailed')
      end
      records = api_result && (api_result['records'] || api_result[:records]) || []
      break if records.blank?

      records.each do |rec|
        outcome = process_call(channel, rec, skip_missed, from, settle: false)
        counts[outcome.is_a?(Symbol) ? outcome : :held] += 1
      rescue StandardError => e
        counts[:failed] += 1
        Rails.logger.error "KC RingCentral Call History: resync failed for a record: #{e.message}"
      end
      break if records.size < 100

      page += 1
      sleep PAGE_SLEEP
    end
    counts
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
      rc_record_auth_failure(channel, 'KC RingCentral Call History', e.message)
      return
    end

    opts        = channel.options.with_indifferent_access
    date_from   = opts[:last_call_history_poll_at].presence || 24.hours.ago.utc.iso8601
    since       = Time.zone.parse(date_from.to_s) || 24.hours.ago
    skip_missed = Setting.get('kc_ringcentral_sms_missed_call_ticket') == true

    counts   = Hash.new(0)
    held     = nil # earliest start of a record we did not file yet
    page     = 1
    fetch_ok = true
    loop do
      begin
        api_result, rc = rc_call_with_auth_recovery(channel, 'KC RingCentral Call History', client: rc) do |client|
          client.get_call_log(date_from: date_from, per_page: 100, type: 'Voice', page: page, view: 'Detailed')
        end
      rescue StandardError => e
        Rails.logger.error "KC RingCentral Call History: Call log query failed for channel #{channel.id}: #{e.message}"
        fetch_ok = false
        break
      end
      if api_result.nil?
        fetch_ok = false
        break
      end

      records = api_result['records'] || api_result[:records] || []
      break if records.blank?

      records.each do |call_record|
        outcome = process_call(channel, call_record, skip_missed, since)
        if outcome.is_a?(Time)
          held = [held, outcome].compact.min
        else
          counts[outcome] += 1
        end
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

    if counts[:created].positive? || counts[:updated].positive?
      Rails.logger.info "KC RingCentral Call History: channel #{channel.id}: #{counts[:created]} call ticket(s) created, #{counts[:updated]} corrected"
    end

    # A failed fetch must not move the watermark, otherwise the calls in the
    # unread window are never fetched.
    if !fetch_ok
      Rails.logger.warn "KC RingCentral Call History: Fetch failed for channel #{channel.id} — watermark not advanced"
      return
    end

    # The watermark lags behind now so RingCentral has time to finalize
    # records, and never passes a record that was held back.
    watermark = FINALIZE_LAG.ago
    watermark = [watermark, held].min if held
    watermark = [watermark, HOLD_LIMIT.ago].max
    channel.with_lock do
      channel.reload
      channel.options[:last_call_history_poll_at] = watermark.utc.iso8601
      channel.save!
    end
  rescue StandardError => e
    Rails.logger.error "KC RingCentral Call History: Failed to update poll watermark for channel #{channel.id}: #{e.message}"
  end

  # Returns :created / :updated / :unchanged / :skipped, or the record's
  # start Time when it must be looked at again on a later run.
  def process_call(channel, call_record, skip_missed, since, settle: true)
    call_record = call_record.with_indifferent_access

    session_id = call_record[:sessionId].to_s
    return :skipped if session_id.blank?

    start_time = begin
                   Time.zone.parse(call_record[:startTime].to_s)
                 rescue ArgumentError, TypeError
                   nil
                 end
    return :skipped if start_time.nil?

    result = call_record[:result].to_s
    return start_time if result.blank? || result == 'In Progress'
    return start_time if settle && start_time > SETTLE_LAG.ago

    inbound     = call_record[:direction].to_s == 'Inbound'
    from_number = normalize_number(call_record.dig(:from, :phoneNumber))
    to_number   = normalize_number(call_record.dig(:to, :phoneNumber))
    legs        = Array(call_record[:legs]).map(&:with_indifferent_access)

    # Everything a call to us is routed to is ours: the number it arrived
    # on and every leg target (the company number behind the IVR, the PBX
    # behind the forward).
    own_numbers([inbound ? to_number : from_number] + legs.map { |l| l.dig(:to, :phoneNumber) }) if inbound
    own_numbers(legs.filter_map { |l| l.dig(:to, :phoneNumber) if l[:legType].to_s == 'FindMe' })

    external = inbound ? from_number : to_number
    return :skipped if external.blank? # internal extension-to-extension call
    # A preliminary record for a call to the company number, or an alert
    # call the PBX placed to us: not a customer.
    return :skipped if own_number?(external)
    return :skipped if !inbound && from_number.present? && !own_number?(from_number)

    # Missed inbound calls belong to the missed-call feature (OPEN tickets)
    return :skipped if inbound && result == 'Missed' && skip_missed
    return :skipped if Ticket::Article.exists?(message_id: "rc_missed_call:#{session_id}")

    duration = call_record[:duration].to_i
    outcome, answered_on, answered_by = summarize(inbound, result, legs, external, start_time, since)

    prefs = {
      session_id:  session_id,
      direction:   call_record[:direction],
      result:      result,
      outcome:     outcome,
      answered_on: answered_on,
      answered_by: answered_by,
      duration:    duration,
      start_time:  call_record[:startTime],
      from_phone:  from_number,
      to_phone:    to_number,
    }

    file_call_record(
      dedup_key:  "rc_call:#{session_id}",
      channel:    channel,
      external:   external,
      inbound:    inbound,
      start_time: start_time,
      duration:   duration,
      outcome:    outcome,
      line:       "#{from_number || call_record.dig(:from, :extensionNumber)} → #{to_number || call_record.dig(:to, :extensionNumber)}",
      prefs_key:  :ringcentral_call,
      prefs:      prefs,
    )
  end

  # [outcome label, answered_on, answered_by]
  def summarize(inbound, result, legs, external, start_time, since)
    return [result, nil, nil] if !inbound

    rc_connected  = legs.any? { |l| l[:legType].to_s != 'FindMe' && l[:result].to_s == 'Call connected' }
    pbx_forwarded = legs.any? { |l| l[:legType].to_s == 'FindMe' }
    pbx_connected = legs.any? { |l| l[:legType].to_s == 'FindMe' && ['Call connected', 'Accepted'].include?(l[:result].to_s) }

    if pbx_forwarded
      pbx = pbx_answer_for(external, start_time, since)
      if pbx[:answered_by]
        return ["Answered on FreePBX by #{describe_extension(pbx[:answered_by], pbx[:answered_by_name])}", 'FreePBX', pbx[:answered_by]]
      end
    end
    return ['Answered on RingCentral', 'RingCentral', nil] if rc_connected
    return ['Answered on FreePBX', 'FreePBX', nil] if pbx_connected

    label = result == 'Accepted' ? 'Missed' : result
    label = 'Missed (forwarded to FreePBX, unanswered)' if pbx_forwarded && label == 'Missed'
    [label, nil, nil]
  end
end
