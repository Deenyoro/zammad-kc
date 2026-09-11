# KC: Channel driver for RingCentral SMS/MMS integration.
#
# This driver handles both inbound (process) and outbound (deliver) message
# flows for SMS/MMS conversations.
#
# Inbound flow:
#   Webhook/Poll → Job → driver.process(adapter_options, message_data, channel)
#   - Deduplicates by RingCentral message ID
#   - Creates or finds customer User by phone number
#   - Threads messages into tickets by conversation key + time window
#   - Creates Ticket::Article with type 'ringcentral_sms_message'
#   - Downloads MMS attachments to Store
#
# Outbound flow:
#   Agent article → Job → driver.deliver(options, article_attributes)
#   - Sends SMS via RingCentral API POST /sms
#   - MMS attachments sent separately (text first, then attachments)
#
# Outbound capture (texts sent from the native RC app, not through Zammad):
#   Webhook/Poll/Backfill → driver.process_outbound(adapter_options, message_data, channel)
#   - Deduplicates by RC message ID (Zammad-sent messages already have articles)
#     and skips texts the system itself sent (Kc::OutboundSms records them)
#   - Attaches to the most recent open ticket for the participants, however
#     old it is; when there is none the text started the conversation, so a
#     ticket is created for it (mirrors the "New SMS" initiator)
#   - Creates an internal note labeled "Sent via RingCentral", with MMS
#     attachments, backdated to the RC send time
#
# Conversation keys:
#   A conversation is the set of phone numbers in it (our number + every other
#   participant), stored as a sorted E.164 list joined by ':'. 1:1 threads keep
#   the historical "our:customer" form; group texts get the full set. Lookups
#   try the full key plus every our:other pair, because older tickets only hold
#   a pair and RingCentral orders a group message's recipients inconsistently.
#
# Articles are backdated to RingCentral's creationTime so a message caught by
# the poll after a newer one arrived by webhook still reads in order (see
# Kc::ChronologicalArticleList).
#
class Channel::Driver::KcRingcentralSms

  CAPTURE_SUFFIX = "\n\n— Sent via RingCentral SMS (not through Zammad)".freeze

  def fetchable?(_channel = nil)
    false
  end

  # Process an inbound RingCentral SMS/MMS message.
  #
  # @param _adapter_options [Hash] channel options (unused — we read from channel directly)
  # @param message_data [Hash] parsed message payload with keys:
  #   :message_id, :from_phone, :to_phone, :to_phones, :text, :direction,
  #   :created_at, :attachments (array of {id:, content_type:, filename:})
  # @param channel [Channel] the RingCentral SMS channel
  # @return [Hash, nil] { ticket:, article: } or nil if duplicate
  def process(_adapter_options, message_data, channel)
    message_data = message_data.with_indifferent_access

    # Dedup: skip if we already have an article with this RC message ID.
    rc_message_id = message_data[:message_id].to_s
    dedup_key     = "rc_sms:#{rc_message_id}"
    return nil if rc_message_id.present? && Ticket::Article.exists?(message_id: dedup_key)

    transaction_class = 'Transaction'.safe_constantize
    if transaction_class.nil?
      Rails.logger.error 'KC RingCentral SMS: Transaction class not found'
      return nil
    end

    from_phone = message_data[:from_phone]
    to_phones  = recipient_list(message_data)
    our_phone  = resolve_our_phone(channel, to_phones)
    others     = other_participants(from_phone, to_phones, our_phone)

    transaction_class.execute(reset_user_id: true, context: 'ringcentral_sms') do
      user   = find_or_create_user(from_phone)
      ticket = find_or_create_ticket(channel, message_data, user, our_phone, others)

      UserInfo.current_user_id = user.id

      article = create_article(ticket, channel, message_data, user, dedup_key, from_phone, our_phone)

      # Download MMS attachments if present
      download_attachments(article, channel, message_data) if message_data[:attachments].present?

      { ticket: ticket, article: article }
    end
  end

  # Process an outbound RingCentral SMS sent from the native RC app (not Zammad).
  #
  # @param _adapter_options [Hash] channel options (unused)
  # @param message_data [Hash] parsed message payload (same keys as #process;
  #   :to_phones holds every recipient of a group text)
  # @param channel [Channel] the RingCentral SMS channel
  # @param mode [Symbol] :live (poll/webhook) or :backfill. Backfill may file a
  #   text on a closed ticket and creates historical tickets closed.
  # @param dry_run [Boolean] when true nothing is written; the plan is returned
  # @return [Hash, nil] { ticket:, article: } (or the plan when dry_run) or nil if skipped
  def process_outbound(_adapter_options, message_data, channel, mode: :live, dry_run: false)
    message_data = message_data.with_indifferent_access
    plan = outbound_capture_plan(channel, message_data, mode: mode)
    return plan if dry_run
    return nil unless %i[attach create].include?(plan[:action])

    transaction_class = 'Transaction'.safe_constantize
    return nil if transaction_class.nil?

    agent = find_agent_for_channel(channel)

    # A backfill files history, not news: keep triggers (Discord webhooks) and
    # agent notifications quiet for it. Live captures behave like any note.
    execute_options = { reset_user_id: true, context: 'ringcentral_sms' }
    execute_options[:disable] = %w[Transaction::Notification Transaction::Trigger] if mode == :backfill

    transaction_class.execute(execute_options) do
      UserInfo.current_user_id = agent.id

      ticket = if plan[:action] == :attach
                 Ticket.find(plan[:ticket_id])
               else
                 create_outbound_ticket(channel, plan, agent)
               end
      previous_updated_at = ticket.updated_at

      article = create_capture_article(ticket, channel, message_data, plan, agent)
      download_attachments(article, channel, message_data) if message_data[:attachments].present?

      # Filing history must not surface the ticket as freshly updated in every
      # overview (nor stretch the thread window it is matched by).
      if mode == :backfill && plan[:action] == :attach
        ticket.update_columns(updated_at: previous_updated_at) # rubocop:disable Rails/SkipsModelValidations
      end

      { ticket: ticket, article: article }
    end
  end

  # Decides what #process_outbound would do for a message without writing.
  # Returns { action: :skip_*|:attach|:create, ... }.
  def outbound_capture_plan(channel, message_data, mode: :live)
    message_data  = message_data.with_indifferent_access
    rc_message_id = message_data[:message_id].to_s
    dedup_key     = "rc_sms:#{rc_message_id}"

    # Zammad-sent texts get their RC message ID stored by the communicate job.
    if rc_message_id.present?
      return { action: :skip_known } if Ticket::Article.exists?(message_id: dedup_key)

      # MMS companions of a Zammad-sent article carry separate RC ids that the
      # communicate job stores in preferences.
      sanitized_rc_id = ActiveRecord::Base.sanitize_sql_like(rc_message_id)
      if Ticket::Article.where('preferences LIKE ?', "%#{sanitized_rc_id}%")
                        .where('preferences LIKE ?', '%mms_message_ids%')
                        .exists?
        return { action: :skip_known }
      end

      sms_class = 'Kc::OutboundSms'.safe_constantize
      return { action: :skip_system } if sms_class.respond_to?(:system_message?) && sms_class.system_message?(channel, rc_message_id)
    end

    # Auto-replies sent before ids were recorded (and any the recording
    # missed) are recognisable by their configured text.
    return { action: :skip_system } if system_text?(message_data[:text])

    to_phones = recipient_list(message_data)
    return { action: :skip_no_recipient } if to_phones.empty?

    our_phone = normalize_phone(message_data[:from_phone].presence || channel.options.with_indifferent_access[:phone_number])
    others    = other_participants(nil, to_phones, our_phone)
    return { action: :skip_no_recipient } if others.empty?

    candidates = conversation_key_candidates(our_phone, others)
    ticket = find_existing_ticket(candidates, 0, include_closed: mode == :backfill)

    base = {
      dedup_key:        dedup_key,
      our_phone:        our_phone,
      others:           others,
      conversation_key: conversation_key(our_phone, *others),
      created_at:       message_data[:created_at],
      mode:             mode,
    }
    if ticket
      base.merge(action: :attach, ticket_id: ticket.id)
    else
      base.merge(action: :create)
    end
  end

  # Deliver an outbound SMS message via RingCentral.
  #
  # @param options [Hash] channel options containing OAuth credentials
  # @param attr [Hash] article attributes (:body, :to_phone, etc.)
  # @param _notification [Boolean] ignored
  # @return [Hash] RingCentral API response
  def deliver(options, attr, _notification = false, channel: nil)
    return if Setting.get('import_mode')

    attr = attr.with_indifferent_access

    rc_class = 'Kc::RingcentralApi'.safe_constantize
    raise 'KC RingCentral SMS: RingcentralApi class not found' if rc_class.nil?

    # Look up channel if not passed (e.g. when called from Zammad's Channel#deliver)
    if channel.nil?
      channel = Channel.find_by(area: 'RingCentralSms::Account', active: true)
      raise 'KC RingCentral SMS: No RingCentral SMS channel found' if channel.nil?
    end

    rc = rc_class.with_channel_tokens(channel)

    from_phone = channel.options.with_indifferent_access[:phone_number]
    to_phone   = attr[:to_phone]
    raise 'Missing to_phone for RingCentral SMS delivery' if to_phone.blank?
    raise 'Missing phone_number in channel options' if from_phone.blank?

    body_text = attr[:body] || ''

    rc.send_sms(from: from_phone, to: to_phone, text: body_text)
  end

  private

  # ------------------------------------------------------------------
  # Participants
  # ------------------------------------------------------------------

  def recipient_list(message_data)
    list = Array(message_data[:to_phones]).presence || [message_data[:to_phone]]
    list.map { |n| normalize_phone(n) }.compact.uniq
  end

  # Every number this channel can text from.
  def owned_numbers(channel)
    opts = channel.options.with_indifferent_access
    ([opts[:phone_number]] + Array(opts[:available_phone_numbers])).map { |n| normalize_phone(n) }.compact.uniq
  end

  # For an inbound message the recipient that is ours: in a group text RC
  # lists our number among the other members' numbers, in no fixed order.
  def resolve_our_phone(channel, to_phones)
    owned = owned_numbers(channel)
    to_phones.find { |n| owned.include?(n) } || to_phones.first || normalize_phone(channel.options.with_indifferent_access[:phone_number])
  end

  # Texts the missed-call jobs send. Compared up to the first placeholder so
  # a template with {phone} or similar still matches.
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
    if rc_class.respond_to?(:conversation_key_candidates)
      return rc_class.conversation_key_candidates(our_phone, others)
    end

    ([conversation_key(our_phone, *others)] + Array(others).map { |o| conversation_key(our_phone, o) }).uniq
  end

  # ------------------------------------------------------------------
  # Users / agents
  # ------------------------------------------------------------------

  def find_or_create_user(phone)
    normalized = normalize_phone(phone)

    # Try to find by phone number
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
    # Try to find an agent/admin user who belongs to this channel's group
    group = Group.find_by(id: channel.group_id)
    if group
      agent = User.joins(:roles, :groups)
                  .where(roles: { name: %w[Agent Admin] })
                  .where(groups: { id: group.id })
                  .where(active: true)
                  .first
    end
    # Broader fallback: any active agent/admin
    agent ||= User.joins(:roles)
                   .where(roles: { name: %w[Agent Admin] })
                   .where(active: true)
                   .first
    agent || User.find(1) # Last resort: system user
  end

  # ------------------------------------------------------------------
  # Tickets
  # ------------------------------------------------------------------

  def find_or_create_ticket(channel, message_data, user, our_phone, others)
    thread_window = thread_window_hours(channel)
    candidates    = conversation_key_candidates(our_phone, others)

    # Look for an existing open ticket matching this conversation
    if candidates.any?
      existing = find_existing_ticket(candidates, thread_window)
      return existing if existing
    end

    # Create new ticket
    group = Group.find_by(id: channel.group_id) || Group.first
    title = build_ticket_title(message_data[:from_phone])

    ticket = Ticket.new(
      title:         title,
      group_id:      group.id,
      customer_id:   user.id,
      state_id:      Ticket::State.find_by(default_create: true)&.id || Ticket::State.find_by(name: 'new')&.id,
      priority_id:   Ticket::Priority.find_by(default_create: true)&.id || Ticket::Priority.first&.id,
      preferences:   {
        ringcentral_sms: {
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
    ticket
  end

  # Ticket for a text the agent started from the RC app. The first other
  # participant is the customer; :from_phone stays the customer's number and
  # :to_phone ours, exactly as an inbound-created ticket, so replies from
  # Zammad go out from the right number.
  def create_outbound_ticket(channel, plan, agent)
    customer_phone = plan[:others].first
    customer       = find_or_create_user(customer_phone)
    group          = Group.find_by(id: channel.group_id) || Group.first
    sent_at        = parse_time(plan[:created_at])

    state = if plan[:mode] == :backfill && sent_at && sent_at < thread_window_hours(channel).hours.ago
              Ticket::State.find_by(name: 'closed')
            end
    state ||= Ticket::State.find_by(default_create: true) || Ticket::State.find_by(name: 'new')

    # Same title as a customer-started thread: the admin template and the
    # triggers that key on it ("SMS from") apply to both.
    ticket = Ticket.new(
      title:         build_ticket_title(customer_phone),
      group_id:      group.id,
      customer_id:   customer.id,
      state_id:      state&.id,
      priority_id:   Ticket::Priority.find_by(default_create: true)&.id || Ticket::Priority.first&.id,
      preferences:   {
        ringcentral_sms: {
          conversation_key: plan[:conversation_key],
          participants:     plan[:others],
          from_phone:       customer_phone,
          to_phone:         plan[:our_phone],
          channel_id:       channel.id,
          agent_initiated:  true,
        },
      },
      updated_by_id: agent.id,
      created_by_id: agent.id,
    )
    ticket.save!
    backdate(ticket, plan[:created_at])
    Rails.logger.info "KC RingCentral SMS: Created ticket #{ticket.id} for agent-initiated text to #{customer_phone}"
    ticket
  end

  # Most recent ticket for any of the candidate keys. thread_window 0 means
  # "however old". include_closed (backfill) also considers closed tickets,
  # open ones first.
  def find_existing_ticket(candidates, thread_window, include_closed: false)
    candidates = Array(candidates).compact.uniq
    return nil if candidates.empty?

    closed_state_ids = Ticket::State
                         .joins(:state_type)
                         .where(ticket_state_types: { name: 'closed' })
                         .select(:id)

    # preferences is YAML; the key is stored quoted, so match the whole value
    # rather than a substring (a pair key is a substring of a group key).
    like_sql  = Array.new(candidates.size, 'preferences LIKE ?').join(' OR ')
    like_args = candidates.map { |key| "%conversation_key: \"#{ActiveRecord::Base.sanitize_sql_like(key)}\"%" }

    scope = Ticket.where(like_sql, *like_args).order(updated_at: :desc)
    scope = scope.where('updated_at >= ?', thread_window.hours.ago) if thread_window.to_i.positive?

    open_ticket = scope.where.not(state_id: closed_state_ids).first
    return open_ticket if open_ticket || !include_closed

    scope.first
  end

  def thread_window_hours(channel)
    channel_window = channel.options&.dig(:thread_window_hours)
    return channel_window.to_i if channel_window.present?

    Setting.get('kc_ringcentral_sms_thread_window_hours')&.to_i || 24
  end

  def build_ticket_title(from_phone)
    template = Setting.get('kc_ringcentral_sms_ticket_title_template').to_s.presence || 'SMS from {phone}'
    phone = normalize_phone(from_phone) || from_phone.to_s
    title = template.gsub('{phone}', phone)
    title.truncate(100, omission: '...')
  end

  # ------------------------------------------------------------------
  # Articles
  # ------------------------------------------------------------------

  def create_article(ticket, channel, message_data, user, dedup_key, from_phone, our_phone)
    article_type = Ticket::Article::Type.find_by(name: 'ringcentral_sms_message')
    sender       = Ticket::Article::Sender.find_by(name: 'Customer') || Ticket::Article::Sender.first

    # Fallback if article type migration hasn't run yet
    if article_type.nil?
      Rails.logger.warn 'KC RingCentral SMS: ringcentral_sms_message article type not found, falling back to note'
      article_type = Ticket::Article::Type.find_by(name: 'note') || Ticket::Article::Type.first
    end

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
        ringcentral_sms: {
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
    article_type = Ticket::Article::Type.find_by(name: 'note') || Ticket::Article::Type.first
    sender       = Ticket::Article::Sender.find_by(name: 'Agent') || Ticket::Article::Sender.first
    text         = message_data[:text].to_s.strip.presence || (message_data[:attachments].present? ? '(MMS)' : '-')

    article = Ticket::Article.new(
      ticket_id:     ticket.id,
      type_id:       article_type&.id,
      sender_id:     sender&.id,
      from:          plan[:our_phone],
      to:            plan[:others].join(', '),
      subject:       nil,
      body:          "#{text}#{CAPTURE_SUFFIX}",
      content_type:  'text/plain',
      message_id:    plan[:dedup_key],
      internal:      true,
      preferences:   {
        ringcentral_sms: {
          message_id:       message_data[:message_id],
          channel_id:       channel.id,
          from_phone:       plan[:our_phone],
          to_phone:         plan[:others].first,
          to_phones:        plan[:others],
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

  # Articles (and tickets) carry RingCentral's send/receive time, not the time
  # the poller happened to see them.
  def backdate(record, raw_time)
    time = parse_time(raw_time)
    return if time.nil?

    record.update_columns(created_at: time, updated_at: time) # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.warn "KC RingCentral SMS: could not backdate #{record.class} #{record.id}: #{e.message}"
  end

  def parse_time(raw)
    return nil if raw.blank?

    Time.zone.parse(raw.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def download_attachments(article, channel, message_data)
    rc_class = 'Kc::RingcentralApi'.safe_constantize
    return if rc_class.nil?

    # Use atomic token refresh — tokens are typically fresh from the caller's
    # with_channel_tokens call, so the 50-min cache will skip the refresh.
    # Critical for the webhook job path which has no prior token refresh.
    rc = rc_class.with_channel_tokens(channel)

    Array(message_data[:attachments]).each do |att|
      begin
        data = rc.get_message_attachment(message_data[:message_id], att[:id])

        # Skip empty/broken attachments (e.g. failed downloads)
        next if data.nil? || data.bytesize < 10

        content_type = att[:content_type] || 'application/octet-stream'
        filename = att[:filename].presence || mms_attachment_filename(att[:id], content_type)

        Store.create!(
          object:      'Ticket::Article',
          o_id:        article.id,
          data:        data,
          filename:    filename,
          preferences: {
            'Content-Type' => content_type,
          },
        )
      rescue => e
        Rails.logger.error "KC RingCentral SMS: Failed to download attachment #{att[:id]}: #{e.message}"
      end
    end
  end

  def normalize_phone(number)
    rc_class = 'Kc::RingcentralApi'.safe_constantize
    return rc_class.normalize_phone(number) if rc_class

    # Inline fallback
    return nil if number.blank?

    digits = number.to_s.gsub(/[^\d+]/, '').delete('+')
    case digits.length
    when 10 then "+1#{digits}"
    when 11 then "+#{digits}"
    else "+#{digits}"
    end
  end

  # Generate a filename with proper extension from content type.
  # RingCentral MMS attachments often have no fileName field.
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
