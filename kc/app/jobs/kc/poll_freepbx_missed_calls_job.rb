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
  include Kc::FreepbxChannelStatus

  # Fallback window when a connection has never polled. It is only ever used
  # together with the connection's created_at guard below, so a freshly added
  # PBX does not backfill an hour of old test calls as tickets and texts.
  LOOKBACK_MINUTES = 60

  # Auto-reply texts that RingCentral refused (token mid-refresh, outage) are
  # retried on later runs rather than dropped. Bounded so a dead SMS channel
  # cannot grow the channel record without limit.
  AUTOREPLY_MAX_ATTEMPTS = 5
  AUTOREPLY_MAX_PENDING  = 100
  AUTOREPLY_MAX_AGE      = 6.hours

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

    retry_pending_autoreplies(channel)

    begin
      calls = api.calls(
        since:         opts[:last_missed_call_poll_at],
        since_minutes: LOOKBACK_MINUTES,
        missed:        true,
        direction:     'inbound',
        limit:         200,
      )
      clear_freepbx_error(channel)
    rescue StandardError => e
      store_freepbx_error(channel, e.message)
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
        process_call(channel, call) if !before_connection?(channel, call)
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

  # Calls that ended before this PBX connection existed are history, not
  # missed calls to act on. The watermark still advances past them.
  def before_connection?(channel, call)
    stamp = call[:calldate_utc].presence || call[:calldate].presence
    return false if stamp.blank? || channel.created_at.blank?

    Time.zone.parse(stamp.to_s) < channel.created_at
  rescue ArgumentError, TypeError
    false
  end

  def process_call(channel, call)
    # One call = one linkedid, however many extensions rang. Fall back to the
    # leg id for connectors that do not report one.
    unique_id = (call[:linkedid].presence || call[:uniqueid]).to_s
    return if unique_id.blank?

    caller = normalize(call[:src].presence || call[:cnum])
    return if caller.blank?

    # Ignore internal extension-to-extension calls; only real callers matter.
    return if caller.to_s.delete('+').length < 7

    dialed = normalize(call[:did].presence || call[:dst])

    # Our own numbers calling in are not customers: the PBX's alert calls
    # carry the RingCentral caller id, and a forwarded call can arrive with
    # our own DID as the source. Ticketing and texting ourselves helps nobody.
    if own_number?(caller, dialed)
      Rails.logger.info "KC FreePBX Missed Calls: Ignoring call #{unique_id} from our own number #{caller}"
      return
    end

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
    sent = Kc::OutboundSms.deliver(to: caller, text: message, from: reply_from,
                                   label: 'KC FreePBX Missed Calls')
    queue_autoreply(channel, unique_id, caller, message, reply_from) if sent.nil?
  end

  # Numbers we own: every RingCentral number in the system plus the DID the
  # call came in on (the PBX's own trunk number).
  def own_number?(caller, dialed)
    ours = Array(Kc::OutboundSms.available_numbers).map { |n| normalize(n.is_a?(Hash) ? (n[:number] || n['number']) : n) }
    ours << dialed if dialed.present?
    ours.compact.include?(caller)
  rescue StandardError => e
    Rails.logger.warn "KC FreePBX Missed Calls: own-number check failed: #{e.message}"
    false
  end

  def queue_autoreply(channel, unique_id, to, text, from)
    channel.with_lock do
      channel.reload
      pending = Array(channel.options[:pending_autoreplies]).map(&:with_indifferent_access)
      return if pending.any? { |p| p[:call_id] == unique_id }

      pending << { call_id: unique_id, to: to, text: text, from: from,
                   queued_at: Time.current.utc.iso8601, attempts: 1 }
      channel.options[:pending_autoreplies] = pending.last(AUTOREPLY_MAX_PENDING)
      channel.save!
    end
    Rails.logger.warn "KC FreePBX Missed Calls: text to #{to} for call #{unique_id} failed, queued for retry"
  rescue StandardError => e
    Rails.logger.error "KC FreePBX Missed Calls: Failed to queue retry for #{to}: #{e.message}"
  end

  def retry_pending_autoreplies(channel)
    pending = Array(channel.options.with_indifferent_access[:pending_autoreplies])
    return if pending.blank?

    keep = []
    pending.each do |item|
      item = item.with_indifferent_access
      queued_at = Time.zone.parse(item[:queued_at].to_s) rescue nil
      if item[:attempts].to_i >= AUTOREPLY_MAX_ATTEMPTS || queued_at.nil? || queued_at < AUTOREPLY_MAX_AGE.ago
        Rails.logger.error "KC FreePBX Missed Calls: giving up on text to #{item[:to]} for call #{item[:call_id]}"
        next
      end

      sent = Kc::OutboundSms.deliver(to: item[:to], text: item[:text], from: item[:from].presence,
                                     label: 'KC FreePBX Missed Calls (retry)')
      next if sent

      item[:attempts] = item[:attempts].to_i + 1
      keep << item
    end

    channel.with_lock do
      channel.reload
      channel.options[:pending_autoreplies] = keep
      channel.save!
    end
  rescue StandardError => e
    Rails.logger.error "KC FreePBX Missed Calls: retry pass failed for channel #{channel.id}: #{e.message}"
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
end
