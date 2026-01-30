# KC: Channel driver for RingCentral SMS/MMS integration.
#
# This driver handles both inbound (process) and outbound (deliver) message
# flows for SMS/MMS conversations.
#
# Inbound flow:
#   Webhook/Poll → Job → driver.process(adapter_options, message_data, channel)
#   - Deduplicates by RingCentral message ID
#   - Creates or finds customer User by phone number
#   - Threads messages into tickets by conversation_key (sorted E.164 pair) + time window
#   - Creates Ticket::Article with type 'ringcentral_sms_message'
#   - Downloads MMS attachments to Store
#
# Outbound flow:
#   Agent article → Job → driver.deliver(options, article_attributes)
#   - Sends SMS via RingCentral API POST /sms
#   - MMS attachments sent separately (text first, then attachments)
#
# Outbound capture (native RC app replies):
#   Poll job → driver.process_outbound(adapter_options, message_data, channel)
#   - Deduplicates by RC message ID (Zammad-sent messages already have articles)
#   - Finds existing ticket by conversation_key; skips if no ticket exists
#   - Creates internal note article labeled "Sent via RingCentral" for context
#
# Hardening:
#   - safe_constantize on all KC/upstream classes
#   - Defensive nil checks throughout
#   - SQL LIKE properly sanitized
#   - Conforms to Zammad's Channel#process call convention
#
class Channel::Driver::KcRingcentralSms

  def fetchable?(_channel = nil)
    false
  end

  # Process an inbound RingCentral SMS/MMS message.
  #
  # @param _adapter_options [Hash] channel options (unused — we read from channel directly)
  # @param message_data [Hash] parsed message payload with keys:
  #   :message_id, :from_phone, :to_phone, :text, :direction,
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

    transaction_class.execute(reset_user_id: true, context: 'ringcentral_sms') do
      from_phone = message_data[:from_phone]
      to_phone   = message_data[:to_phone]

      user   = find_or_create_user(from_phone)
      ticket = find_or_create_ticket(channel, message_data, user, from_phone, to_phone)

      UserInfo.current_user_id = user.id

      article = create_article(ticket, channel, message_data, user, dedup_key, from_phone)

      # Download MMS attachments if present
      download_attachments(article, channel, message_data) if message_data[:attachments].present?

      { ticket: ticket, article: article }
    end
  end

  # Process an outbound RingCentral SMS sent from the native RC app (not Zammad).
  #
  # Creates an internal note on the matching ticket so agents can see the
  # full conversation context. Zammad-sent outbound messages are skipped
  # via dedup (their RC message ID is already stored on the article by
  # the communicate job).
  #
  # @param _adapter_options [Hash] channel options (unused)
  # @param message_data [Hash] parsed message payload
  # @param channel [Channel] the RingCentral SMS channel
  # @return [Hash, nil] { ticket:, article: } or nil if skipped
  def process_outbound(_adapter_options, message_data, channel)
    message_data = message_data.with_indifferent_access

    # Dedup: skip if we already have an article with this RC message ID.
    # Zammad-sent outbound messages get their RC message ID stored by the communicate job.
    rc_message_id = message_data[:message_id].to_s
    dedup_key     = "rc_sms:#{rc_message_id}"
    return nil if rc_message_id.present? && Ticket::Article.exists?(message_id: dedup_key)

    # Find existing ticket by conversation_key — don't create tickets for outbound
    from_phone = message_data[:from_phone]
    to_phone   = message_data[:to_phone]
    return nil if to_phone.blank?

    rc_class = 'Kc::RingcentralApi'.safe_constantize
    conversation_key = if rc_class
                         rc_class.conversation_key(from_phone, to_phone)
                       else
                         [normalize_phone(from_phone), normalize_phone(to_phone)].compact.sort.join(':')
                       end

    thread_window = thread_window_hours(channel)
    ticket = find_existing_ticket(conversation_key, thread_window) if conversation_key.present?
    if ticket.nil?
      Rails.logger.debug "KC RingCentral SMS: Skipping outbound message #{rc_message_id} — no matching ticket"
      return nil
    end

    # Find the agent user who owns this phone number (sender), fall back to system user
    agent = find_agent_for_channel(channel)

    transaction_class = 'Transaction'.safe_constantize
    return nil if transaction_class.nil?

    transaction_class.execute(reset_user_id: true, context: 'ringcentral_sms') do
      UserInfo.current_user_id = agent.id

      article_type = Ticket::Article::Type.find_by(name: 'note') || Ticket::Article::Type.first
      sender       = Ticket::Article::Sender.find_by(name: 'Agent')

      article = Ticket::Article.new(
        ticket_id:     ticket.id,
        type_id:       article_type&.id,
        sender_id:     sender&.id,
        from:          normalize_phone(from_phone) || from_phone.to_s,
        subject:       nil,
        body:          "#{message_data[:text]}\n\n— Sent via RingCentral SMS (not through Zammad)",
        content_type:  'text/plain',
        message_id:    dedup_key,
        internal:      true,
        preferences:   {
          ringcentral_sms: {
            message_id:      message_data[:message_id],
            channel_id:      channel.id,
            from_phone:      normalize_phone(from_phone),
            to_phone:        normalize_phone(to_phone),
            outbound_capture: true,
          },
        },
        updated_by_id: agent.id,
        created_by_id: agent.id,
      )
      article.save!

      { ticket: ticket, article: article }
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

    options = options.with_indifferent_access
    attr    = attr.with_indifferent_access

    rc_class = 'Kc::RingcentralApi'.safe_constantize
    raise 'KC RingCentral SMS: RingcentralApi class not found' if rc_class.nil?

    rc = rc_class.new(
      client_id:     options[:client_id],
      client_secret: options[:client_secret],
      access_token:  options[:access_token],
      refresh_token: options[:refresh_token],
    )
    rc.refresh_access_token!

    # RingCentral rotates refresh tokens — persist new tokens back to channel.
    if channel.present?
      channel.with_lock do
        channel.reload
        channel.options[:access_token]  = rc.access_token
        channel.options[:refresh_token] = rc.refresh_token
        channel.save!
      end
    end

    from_phone = options[:phone_number]
    to_phone   = attr[:to_phone]
    raise 'Missing to_phone for RingCentral SMS delivery' if to_phone.blank?
    raise 'Missing phone_number in channel options' if from_phone.blank?

    body_text = attr[:body] || ''

    rc.send_sms(from: from_phone, to: to_phone, text: body_text)
  end

  private

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

  def find_or_create_ticket(channel, message_data, user, from_phone, to_phone)
    rc_class = 'Kc::RingcentralApi'.safe_constantize
    conversation_key = if rc_class
                         rc_class.conversation_key(from_phone, to_phone)
                       else
                         [normalize_phone(from_phone), normalize_phone(to_phone)].compact.sort.join(':')
                       end

    thread_window = thread_window_hours(channel)

    # Look for an existing open ticket matching this conversation
    if conversation_key.present?
      existing = find_existing_ticket(conversation_key, thread_window)
      return existing if existing
    end

    # Create new ticket
    group = Group.find_by(id: channel.group_id) || Group.first
    title = build_ticket_title(from_phone)

    ticket = Ticket.new(
      title:         title,
      group_id:      group.id,
      customer_id:   user.id,
      state_id:      Ticket::State.find_by(default_create: true)&.id || Ticket::State.find_by(name: 'new')&.id,
      priority_id:   Ticket::Priority.find_by(default_create: true)&.id || Ticket::Priority.first&.id,
      preferences:   {
        ringcentral_sms: {
          conversation_key: conversation_key,
          from_phone:       normalize_phone(from_phone),
          to_phone:         normalize_phone(to_phone),
        },
      },
      updated_by_id: user.id,
      created_by_id: user.id,
    )
    ticket.save!
    ticket
  end

  def create_article(ticket, channel, message_data, user, dedup_key, from_phone)
    article_type = Ticket::Article::Type.find_by(name: 'ringcentral_sms_message')
    sender       = Ticket::Article::Sender.find_by(name: 'Customer')

    # Fallback if article type migration hasn't run yet
    if article_type.nil?
      Rails.logger.warn 'KC RingCentral SMS: ringcentral_sms_message article type not found, falling back to note'
      article_type = Ticket::Article::Type.find_by(name: 'note')
    end

    article = Ticket::Article.new(
      ticket_id:     ticket.id,
      type_id:       article_type&.id,
      sender_id:     sender&.id,
      from:          normalize_phone(from_phone),
      subject:       nil,
      body:          message_data[:text] || '',
      content_type:  'text/plain',
      message_id:    dedup_key,
      internal:      false,
      preferences:   {
        ringcentral_sms: {
          message_id: message_data[:message_id],
          channel_id: channel.id,
          from_phone: normalize_phone(from_phone),
          to_phone:   normalize_phone(message_data[:to_phone]),
        },
      },
      updated_by_id: user.id,
      created_by_id: user.id,
    )
    article.save!
    article
  end

  def download_attachments(article, channel, message_data)
    rc_class = 'Kc::RingcentralApi'.safe_constantize
    return if rc_class.nil?

    opts = channel.options.with_indifferent_access
    rc = rc_class.new(
      client_id:     opts[:client_id],
      client_secret: opts[:client_secret],
      access_token:  opts[:access_token],
      refresh_token: opts[:refresh_token],
    )

    Array(message_data[:attachments]).each do |att|
      begin
        data = rc.get_message_attachment(message_data[:message_id], att[:id])

        Store.create!(
          object:      'Ticket::Article',
          o_id:        article.id,
          data:        data,
          filename:    att[:filename] || "attachment_#{att[:id]}",
          preferences: {
            'Content-Type' => att[:content_type] || 'application/octet-stream',
          },
        )
      rescue => e
        Rails.logger.error "KC RingCentral SMS: Failed to download attachment #{att[:id]}: #{e.message}"
      end
    end
  end

  def build_ticket_title(from_phone)
    template = Setting.get('kc_ringcentral_sms_ticket_title_template').to_s.presence || 'SMS from {phone}'
    phone = normalize_phone(from_phone) || from_phone.to_s
    title = template.gsub('{phone}', phone)
    title.truncate(100, omission: '...')
  end

  def find_existing_ticket(conversation_key, thread_window)
    sanitized_key = ActiveRecord::Base.sanitize_sql_like(conversation_key)

    closed_state_ids = Ticket::State
                         .joins(:state_type)
                         .where(ticket_state_types: { name: 'closed' })
                         .select(:id)

    scope = Ticket.where('preferences LIKE ?', "%#{sanitized_key}%")
                  .where.not(state_id: closed_state_ids)
                  .order(updated_at: :desc)

    # If thread_window is 0, always return the most recent open ticket
    if thread_window == 0
      return scope.first
    end

    cutoff = thread_window.hours.ago
    scope.where('updated_at >= ?', cutoff).first
  end

  def thread_window_hours(channel)
    channel_window = channel.options&.dig(:thread_window_hours)
    return channel_window.to_i if channel_window.present?

    Setting.get('kc_ringcentral_sms_thread_window_hours')&.to_i || 24
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

end
