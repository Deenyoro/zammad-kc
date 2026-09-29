# KC: Channel driver for the FreePBX phone integration.
#
# Zammad's generic channel loop fetches every active channel whose area ends
# in "::Account". FreePBX call activity is polled on its own schedule by
# Kc::PollFreepbxMissedCallsJob, so this driver opts out of that loop; without
# it, every fetch cycle would fail to resolve a driver and permanently mark
# the channel as errored.
#
# Text messages (kc_freepbx_sms_enabled) go through the KC PBX connector,
# which fronts the PBX's SMS module (see Kc::FreepbxApi for the contract).
# The flows mirror Channel::Driver::KcRingcentralSms:
#
# Inbound:
#   Webhook/Poll → Job → driver.process(adapter_options, message_data, channel)
#   - Deduplicates by connector message id ("fpbx_sms:<id>")
#   - Creates or finds the customer by phone number
#   - Threads messages into tickets by conversation key + time window
#   - Creates Ticket::Article with type 'freepbx_sms_message'
#   - Downloads MMS media to Store
#
# Outbound:
#   Agent article → Kc::CommunicateFreepbxSmsJob → driver.deliver
#
# Outbound capture (texts sent from UCP / Sangoma Connect, not Zammad):
#   Webhook/Poll/Backfill → driver.process_outbound
#   - Skips texts Zammad or the system sent, attaches the rest to the most
#     recent open ticket for the participants as an internal note. Never
#     opens a ticket: only incoming texts do that.
#
# message_data keys: :message_id, :from_phone, :to_phone, :to_phones, :text,
#   :direction ('inbound'/'outbound'), :created_at, :extension,
#   :attachments (array of { id:, url:, content_type:, filename: })
class Channel::Driver::KcFreepbx

  PREFS_KEY      = :freepbx_sms
  DEDUP_PREFIX   = 'fpbx_sms:'.freeze
  ARTICLE_TYPE   = 'freepbx_sms_message'.freeze
  CAPTURE_SUFFIX = "\n\n— Sent via FreePBX SMS (not through Zammad)".freeze

  def fetchable?(_channel = nil)
    false
  end

  # Nothing to fetch on Zammad's schedule; the KC scheduler jobs own polling.
  def fetch(_options = nil, _channel = nil)
    { result: 'ok', notice: 'FreePBX is polled by the KC scheduler jobs.' }
  end

  # ------------------------------------------------------------------
  # Inbound
  # ------------------------------------------------------------------

  # @return [Hash, nil] { ticket:, article: } or nil when already known
  def process(_adapter_options, message_data, channel)
    message_data = message_data.with_indifferent_access

    dedup_key = dedup_key_for(message_data[:message_id])
    return nil if dedup_key.present? && Ticket::Article.exists?(message_id: dedup_key)

    transaction_class = 'Transaction'.safe_constantize
    if transaction_class.nil?
      Rails.logger.error 'KC FreePBX SMS: Transaction class not found'
      return nil
    end

    from_phone = message_data[:from_phone]
    to_phones  = recipient_list(message_data)
    our_phone  = resolve_our_phone(channel, to_phones)
    others     = other_participants(from_phone, to_phones, our_phone)

    transaction_class.execute(reset_user_id: true, context: 'freepbx_sms') do
      user   = find_or_create_user(from_phone)
      ticket = find_or_create_ticket(channel, message_data, user, our_phone, others)

      UserInfo.current_user_id = user.id

      article = create_article(ticket, channel, message_data, user, dedup_key, from_phone, our_phone)
      download_attachments(article, channel, message_data) if message_data[:attachments].present?

      { ticket: ticket, article: article }
    end
  end

  # ------------------------------------------------------------------
  # Outbound capture
  # ------------------------------------------------------------------

  def process_outbound(_adapter_options, message_data, channel, mode: :live, dry_run: false)
    message_data = message_data.with_indifferent_access
    plan = outbound_capture_plan(channel, message_data, mode: mode)
    return plan if dry_run
    return nil unless plan[:action] == :attach

    transaction_class = 'Transaction'.safe_constantize
    return nil if transaction_class.nil?

    agent = find_agent_for_channel(channel)

    execute_options = { reset_user_id: true, context: 'freepbx_sms' }
    execute_options[:disable] = %w[Transaction::Notification Transaction::Trigger] if mode == :backfill

    transaction_class.execute(execute_options) do
      UserInfo.current_user_id = agent.id

      ticket  = Ticket.find(plan[:ticket_id])
      article = create_capture_article(ticket, channel, message_data, plan, agent)
      download_attachments(article, channel, message_data) if message_data[:attachments].present?

      { ticket: ticket, article: article }
    end
  end

  # Decides what #process_outbound would do without writing.
  def outbound_capture_plan(channel, message_data, mode: :live)
    message_data = message_data.with_indifferent_access
    dedup_key    = dedup_key_for(message_data[:message_id])

    if dedup_key.present?
      return { action: :skip_known } if Ticket::Article.exists?(message_id: dedup_key)

      sms_class = 'Kc::OutboundSms'.safe_constantize
      if sms_class.respond_to?(:system_message?) && sms_class.system_message?(channel, message_data[:message_id])
        return { action: :skip_system }
      end
    end
    return { action: :skip_system } if system_text?(message_data[:text])

    to_phones = recipient_list(message_data)
    return { action: :skip_no_recipient } if to_phones.empty?

    our_phone = normalize_phone(message_data[:from_phone].presence || default_number(channel))
    others    = other_participants(nil, to_phones, our_phone)
    return { action: :skip_no_recipient } if others.empty?

    ticket = find_existing_ticket(conversation_key_candidates(our_phone, others), 0, include_closed: mode == :backfill)

    base = {
      dedup_key:        dedup_key,
      our_phone:        our_phone,
      others:           others,
      conversation_key: conversation_key(our_phone, *others),
      created_at:       message_data[:created_at],
      mode:             mode,
    }
    ticket ? base.merge(action: :attach, ticket_id: ticket.id) : base.merge(action: :skip_no_ticket)
  end

  # ------------------------------------------------------------------
  # Outbound delivery
  # ------------------------------------------------------------------

  # @param attr [Hash] :body, :to_phone / :to_phones, :from_phone, :media
  # @return [Hash] connector response ({ id: })
  def deliver(_options, attr, _notification = false, channel: nil)
    return if Setting.get('import_mode')

    attr = attr.with_indifferent_access

    api_class = 'Kc::FreepbxApi'.safe_constantize
    raise 'KC FreePBX SMS: FreepbxApi class not found' if api_class.nil?

    if channel.nil?
      channel = Channel.find_by(area: 'Freepbx::Account', active: true)
      raise 'KC FreePBX SMS: No FreePBX connection found' if channel.nil?
    end

    to_phones  = Array(attr[:to_phones]).presence || [attr[:to_phone]]
    to_phones  = to_phones.map { |n| normalize_phone(n) }.compact.uniq
    from_phone = normalize_phone(attr[:from_phone].presence || default_number(channel))
    raise 'Missing to_phone for FreePBX SMS delivery' if to_phones.empty?
    raise 'No FreePBX texting number configured' if from_phone.blank?

    api_class.for_channel(channel).sms_send(from: from_phone, to: to_phones, text: attr[:body].to_s, media: Array(attr[:media]))
  end

  private

  # ------------------------------------------------------------------
  # Participants
  # ------------------------------------------------------------------

  def dedup_key_for(message_id)
    id = message_id.to_s
    id.present? ? "#{DEDUP_PREFIX}#{id}" : nil
  end

  def recipient_list(message_data)
    list = Array(message_data[:to_phones]).presence || [message_data[:to_phone]]
    list.map { |n| normalize_phone(n) }.compact.uniq
  end

  # Every number this connection can text from: the list the connector
  # reported last, plus the configured default.
  def owned_numbers(channel)
    opts    = channel.options.with_indifferent_access
    numbers = Array(opts[:sms_numbers]).map { |n| n.is_a?(Hash) ? (n[:number] || n['number']) : n }
    ([default_number(channel)] + numbers).map { |n| normalize_phone(n) }.compact.uniq
  end

  def default_number(channel)
    opts = channel.options.with_indifferent_access
    opts[:sms_default_number].presence ||
      Setting.get('kc_freepbx_sms_default_number').to_s.presence ||
      Array(opts[:sms_numbers]).map { |n| n.is_a?(Hash) ? (n[:number] || n['number']) : n }.first
  end

  def resolve_our_phone(channel, to_phones)
    owned = owned_numbers(channel)
    to_phones.find { |n| owned.include?(n) } || to_phones.first || normalize_phone(default_number(channel))
  end

  # Texts the missed-call jobs send.
  def system_text?(text)
    body = text.to_s.strip
    return false if body.blank?

    templates = [
      Setting.get('kc_ringcentral_sms_missed_call_autoreply_message'),
      Setting.get('kc_freepbx_missed_call_autoreply_message'),
      'We are sorry for missing your call. A ticket has been created and our team will follow up with you shortly.',
    ]
    templates.any? do |template|
      prefix = template.to_s.split('{').first.to_s.strip
      prefix.present? && body.start_with?(prefix)
    end
  rescue StandardError
    false
  end

  def other_participants(from_phone, to_phones, our_phone)
    ([from_phone] + Array(to_phones)).map { |n| normalize_phone(n) }.compact.uniq - [our_phone].compact
  end

  def conversation_key(*numbers)
    rc_class = 'Kc::RingcentralApi'.safe_constantize
    return rc_class.conversation_key(*numbers) if rc_class

    numbers.flatten.map { |n| normalize_phone(n) }.compact.uniq.sort.join(':')
  end

  def conversation_key_candidates(our_phone, others)
    rc_class = 'Kc::RingcentralApi'.safe_constantize
    return rc_class.conversation_key_candidates(our_phone, others) if rc_class.respond_to?(:conversation_key_candidates)

    ([conversation_key(our_phone, *others)] + Array(others).map { |o| conversation_key(our_phone, o) }).uniq
  end

  # ------------------------------------------------------------------
  # Users / agents
  # ------------------------------------------------------------------

  def find_or_create_user(phone)
    normalized = normalize_phone(phone)

    user = User.find_by(phone: normalized) || User.find_by(mobile: normalized)
    return user if user

    User.create!(
      firstname:     normalized,
      lastname:      '',
      phone:         normalized,
      active:        true,
      role_ids:      Role.signup_role_ids,
      updated_by_id: 1,
      created_by_id: 1,
    )
  end

  def find_agent_for_channel(channel)
    group = Group.find_by(id: channel.group_id)
    if group
      agent = User.joins(:roles, :groups)
                  .where(roles: { name: %w[Agent Admin] })
                  .where(groups: { id: group.id })
                  .where(active: true)
                  .first
    end
    agent ||= User.joins(:roles)
                  .where(roles: { name: %w[Agent Admin] })
                  .where(active: true)
                  .first
    agent || User.find(1)
  end

  # ------------------------------------------------------------------
  # Tickets
  # ------------------------------------------------------------------

  def find_or_create_ticket(channel, message_data, user, our_phone, others)
    candidates = conversation_key_candidates(our_phone, others)
    if candidates.any?
      existing = find_existing_ticket(candidates, thread_window_hours(channel))
      return existing if existing
    end

    group = Group.find_by(id: channel.group_id) || Group.first
    title = build_ticket_title(message_data[:from_phone])

    ticket = Ticket.new(
      title:         title,
      group_id:      group.id,
      customer_id:   user.id,
      state_id:      Ticket::State.find_by(default_create: true)&.id || Ticket::State.find_by(name: 'new')&.id,
      priority_id:   Ticket::Priority.find_by(default_create: true)&.id || Ticket::Priority.first&.id,
      preferences:   {
        PREFS_KEY => {
          conversation_key: conversation_key(our_phone, *others),
          participants:     others,
          from_phone:       normalize_phone(message_data[:from_phone]),
          to_phone:         our_phone,
          channel_id:       channel.id,
        },
      },
      updated_by_id: user.id,
      created_by_id: user.id,
    )
    ticket.save!
    backdate(ticket, message_data[:created_at])
    add_context_note(ticket, channel, our_phone, others, before: message_data[:created_at], exclude_id: message_data[:message_id])
    ticket
  end

  # ------------------------------------------------------------------
  # Conversation context on new tickets
  # ------------------------------------------------------------------

  CONTEXT_FETCH_LIMIT = 100

  def context_message_count
    Setting.get('kc_freepbx_sms_context_messages').to_i.clamp(0, 50)
  rescue StandardError
    5
  end

  # One internal note with the last N messages of this conversation from
  # before the message that opened the ticket. Never raises.
  def add_context_note(ticket, channel, our_phone, others, before:, exclude_id: nil)
    count = context_message_count
    return if count.zero?

    api_class = 'Kc::FreepbxApi'.safe_constantize
    return if api_class.nil?

    ours      = normalize_phone(our_phone)
    allowed   = ([ours] + Array(others).map { |n| normalize_phone(n) }).compact.uniq
    before_at = parse_time(before) || Time.current

    records = begin
      api_class.for_channel(channel).sms_messages(since_minutes: 60 * 24 * 90, limit: CONTEXT_FETCH_LIMIT * 4)
    rescue StandardError => e
      Rails.logger.warn "KC FreePBX SMS: context fetch failed: #{e.message}"
      []
    end

    messages = records.map(&:with_indifferent_access).select do |m|
      next false if exclude_id.present? && m[:id].to_s == exclude_id.to_s

      at = parse_time(m[:created_at])
      next false if at.nil? || at >= before_at

      participants = ([m[:from]] + Array(m[:to])).map { |n| normalize_phone(n) }.compact.uniq
      (participants - allowed).empty? && (participants & (allowed - [ours])).any?
    end

    messages = messages.sort_by { |m| m[:created_at].to_s }.last(count)
    return if messages.empty?

    lines = messages.map do |m|
      time   = parse_time(m[:created_at])&.strftime('%Y-%m-%d %H:%M') || '?'
      sender = m[:direction].to_s == 'outbound' ? "#{normalize_phone(m[:from])} (us)" : normalize_phone(m[:from]).to_s
      text   = [m[:text].to_s.strip.presence, (Array(m[:media]).any? ? '[MMS attachment]' : nil)].compact.join(' ')
      "[#{time}] #{sender}: #{text.presence || '-'}"
    end

    body = "Earlier conversation (last #{messages.size} message#{'s' if messages.size != 1} before this ticket):\n\n#{lines.join("\n")}"
    create_context_article(ticket, body, messages.first[:created_at])
  rescue StandardError => e
    Rails.logger.warn "KC FreePBX SMS: could not add context note to ticket #{ticket.id}: #{e.message}"
  end

  def create_context_article(ticket, body, first_time)
    article = Ticket::Article.new(
      ticket_id:     ticket.id,
      type_id:       (Ticket::Article::Type.find_by(name: 'note') || Ticket::Article::Type.first)&.id,
      sender_id:     (Ticket::Article::Sender.find_by(name: 'System') || Ticket::Article::Sender.find_by(name: 'Agent'))&.id,
      from:          'FreePBX SMS',
      subject:       'Conversation context',
      body:          body,
      content_type:  'text/plain',
      internal:      true,
      preferences:   { PREFS_KEY => { context_note: true } },
      updated_by_id: 1,
      created_by_id: 1,
    )
    article.save!
    first = parse_time(first_time)
    backdate(article, (first || ticket.created_at) - 1.second)
    article
  end

  # Most recent FreePBX SMS ticket for any of the candidate keys.
  # thread_window 0 means "however old".
  def find_existing_ticket(candidates, thread_window, include_closed: false)
    candidates = Array(candidates).compact.uniq
    return nil if candidates.empty?

    closed_state_ids = Ticket::State
                         .joins(:state_type)
                         .where(ticket_state_types: { name: 'closed' })
                         .select(:id)

    like_sql  = Array.new(candidates.size, 'preferences LIKE ?').join(' OR ')
    like_args = candidates.map { |key| "%conversation_key: \"#{ActiveRecord::Base.sanitize_sql_like(key)}\"%" }

    scope = Ticket.where('preferences LIKE ?', "%#{PREFS_KEY}:%")
                  .where(like_sql, *like_args)
                  .order(updated_at: :desc)
    scope = scope.where('updated_at >= ?', thread_window.hours.ago) if thread_window.to_i.positive?

    open_ticket = scope.where.not(state_id: closed_state_ids).first
    return open_ticket if open_ticket || !include_closed

    scope.first
  end

  def thread_window_hours(channel)
    channel_window = channel.options&.dig(:sms_thread_window_hours)
    return channel_window.to_i if channel_window.present?

    Setting.get('kc_freepbx_sms_thread_window_hours')&.to_i || 24
  end

  def build_ticket_title(from_phone)
    template = Setting.get('kc_freepbx_sms_ticket_title_template').to_s.presence || 'SMS from {phone}'
    phone    = normalize_phone(from_phone) || from_phone.to_s
    template.gsub('{phone}', phone).truncate(100, omission: '...')
  end

  # ------------------------------------------------------------------
  # Articles
  # ------------------------------------------------------------------

  def create_article(ticket, channel, message_data, user, dedup_key, from_phone, our_phone)
    article_type = Ticket::Article::Type.find_by(name: ARTICLE_TYPE)
    if article_type.nil?
      Rails.logger.warn "KC FreePBX SMS: #{ARTICLE_TYPE} article type not found, falling back to note"
      article_type = Ticket::Article::Type.find_by(name: 'note') || Ticket::Article::Type.first
    end
    sender = Ticket::Article::Sender.find_by(name: 'Customer') || Ticket::Article::Sender.first

    article = Ticket::Article.new(
      ticket_id:     ticket.id,
      type_id:       article_type&.id,
      sender_id:     sender&.id,
      from:          normalize_phone(from_phone),
      subject:       nil,
      body:          message_data[:text].to_s.strip.presence || (message_data[:attachments].present? ? '(MMS)' : '-'),
      content_type:  'text/plain',
      message_id:    dedup_key,
      internal:      false,
      preferences:   {
        PREFS_KEY => {
          message_id: message_data[:message_id],
          channel_id: channel.id,
          from_phone: normalize_phone(from_phone),
          to_phone:   our_phone,
          to_phones:  recipient_list(message_data),
        },
      },
      updated_by_id: user.id,
      created_by_id: user.id,
    )
    article.save!
    backdate(article, message_data[:created_at])
    article
  end

  def create_capture_article(ticket, channel, message_data, plan, agent)
    text = message_data[:text].to_s.strip.presence || (message_data[:attachments].present? ? '(MMS)' : '-')
    sent_by = message_data[:extension].present? ? " (ext #{message_data[:extension]})" : ''

    article = Ticket::Article.new(
      ticket_id:     ticket.id,
      type_id:       (Ticket::Article::Type.find_by(name: 'note') || Ticket::Article::Type.first)&.id,
      sender_id:     (Ticket::Article::Sender.find_by(name: 'Agent') || Ticket::Article::Sender.first)&.id,
      from:          plan[:our_phone],
      to:            plan[:others].join(', '),
      subject:       nil,
      body:          "#{text}#{CAPTURE_SUFFIX}#{sent_by}",
      content_type:  'text/plain',
      message_id:    plan[:dedup_key],
      internal:      true,
      preferences:   {
        PREFS_KEY => {
          message_id:       message_data[:message_id],
          channel_id:       channel.id,
          from_phone:       plan[:our_phone],
          to_phone:         plan[:others].first,
          to_phones:        plan[:others],
          extension:        message_data[:extension],
          outbound_capture: true,
        },
      },
      updated_by_id: agent.id,
      created_by_id: agent.id,
    )
    article.save!
    backdate(article, message_data[:created_at])
    article
  end

  # Articles (and tickets) carry the PBX's send/receive time, not the time
  # the poller happened to see them.
  def backdate(record, raw_time)
    time = parse_time(raw_time)
    return if time.nil?

    record.update_columns(created_at: time, updated_at: time) # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.warn "KC FreePBX SMS: could not backdate #{record.class} #{record.id}: #{e.message}"
  end

  def parse_time(raw)
    return nil if raw.blank?

    Time.zone.parse(raw.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def download_attachments(article, channel, message_data)
    api_class = 'Kc::FreepbxApi'.safe_constantize
    return if api_class.nil?

    api = api_class.for_channel(channel)
    Array(message_data[:attachments]).each do |att|
      att = att.with_indifferent_access
      location = att[:url].presence || (att[:id].present? ? "/sms/media/#{att[:id]}" : nil)
      next if location.blank?

      begin
        data = api.sms_media(location)
        next if data.nil? || data.bytesize < 10

        content_type = att[:content_type].presence || 'application/octet-stream'
        Store.create!(
          object:      'Ticket::Article',
          o_id:        article.id,
          data:        data,
          filename:    att[:filename].presence || mms_attachment_filename(att[:id] || Digest::MD5.hexdigest(location), content_type),
          preferences: { 'Content-Type' => content_type },
        )
      rescue StandardError => e
        Rails.logger.error "KC FreePBX SMS: Failed to download media #{location}: #{e.message}"
      end
    end
  end

  def normalize_phone(number)
    rc_class = 'Kc::RingcentralApi'.safe_constantize
    return rc_class.normalize_phone(number) if rc_class
    return nil if number.blank?

    digits = number.to_s.gsub(/[^\d+]/, '').delete('+')
    case digits.length
    when 10 then "+1#{digits}"
    else "+#{digits}"
    end
  end

  def mms_attachment_filename(attachment_id, content_type)
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
          else
            subtype = content_type.to_s.split('/').last
            subtype.present? && subtype != 'octet-stream' ? ".#{subtype}" : ''
          end
    "mms_#{attachment_id}#{ext}"
  end
end
