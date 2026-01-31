# KC: Channel driver for Microsoft Teams Chat integration.
#
# This driver handles both inbound (process) and outbound (deliver) message
# flows for Teams chat conversations.
#
# Inbound flow:
#   Webhook/Poll → Job → driver.process(adapter_options, message_data, channel)
#   - Deduplicates by Graph message ID
#   - Creates or finds User from Teams user info
#   - Threads messages into tickets by conversation_key + time window
#   - Customer messages: creates Ticket::Article with type 'teams_chat_message'
#   - Agent messages (sent from Teams app, not Zammad): creates internal note
#     labeled "Sent via Teams" for conversation context
#
# Outbound flow:
#   Agent article → Job → driver.deliver(options, article_attributes)
#   - Sends message via Graph API POST /chats/{id}/messages
#
# Hardening:
#   - safe_constantize on all KC/upstream classes that could be renamed
#   - Defensive nil checks throughout
#   - SQL LIKE properly sanitized
#   - Conforms to Zammad's Channel#process call convention:
#       driver.process(adapter_options, params, channel)
#
class Channel::Driver::KcMicrosoftTeamsChat

  def fetchable?(_channel = nil)
    false
  end

  # Process an inbound Teams chat message.
  #
  # Conforms to Zammad's Channel#process call convention:
  #   driver.process(adapter_options, params, channel)
  #
  # The jobs also call this method directly with the same signature.
  #
  # @param _adapter_options [Hash] channel options (unused — we read from channel directly)
  # @param message_data [Hash] parsed Graph message payload with keys:
  #   :chat_id, :message_id, :from_user_id, :from_display_name,
  #   :from_email, :body_content, :body_content_type, :created_at,
  #   :tenant_id
  # @param channel [Channel] the Teams Chat channel
  # @return [Hash, nil] { ticket:, article: } or nil if duplicate
  def process(_adapter_options, message_data, channel)
    message_data = message_data.with_indifferent_access

    # Dedup: skip if we already have an article with this Graph message ID.
    message_id = "teams_chat:#{message_data[:message_id]}"
    return nil if Ticket::Article.exists?(message_id: message_id)

    transaction_class = 'Transaction'.safe_constantize
    if transaction_class.nil?
      Rails.logger.error 'KC Teams Chat: Transaction class not found'
      return nil
    end

    # Agent messages: find existing ticket only (don't create new ones for outbound context)
    if message_data[:is_agent]
      ticket = nil
      conversation_key = build_conversation_key(channel, message_data)
      if conversation_key.present?
        thread_window = thread_window_hours(channel)
        ticket = find_existing_ticket(conversation_key, thread_window)
      end

      if ticket.nil?
        Rails.logger.debug "KC Teams Chat: Skipping agent message #{message_data[:message_id]} — no matching ticket"
        return nil
      end

      transaction_class.execute(reset_user_id: true, context: 'teams_chat') do
        user = find_or_create_user(message_data)
        UserInfo.current_user_id = user.id
        article = create_agent_article(ticket, channel, message_data, user, message_id)
        { ticket: ticket, article: article }
      end
    else
      transaction_class.execute(reset_user_id: true, context: 'teams_chat') do
        user   = find_or_create_user(message_data)
        ticket = find_or_create_ticket(channel, message_data, user)
        UserInfo.current_user_id = user.id
        article = create_article(ticket, channel, message_data, user, message_id)
        { ticket: ticket, article: article }
      end
    end
  end

  # Deliver an outbound message to a Teams chat.
  #
  # @param options [Hash] channel options containing OAuth credentials
  # @param attr [Hash] article attributes (:body, :chat_id, etc.)
  # @param _notification [Boolean] ignored
  # @return [Hash] Graph API response with created message data
  def deliver(options, attr, _notification = false)
    return if Setting.get('import_mode')

    options = options.with_indifferent_access
    attr    = attr.with_indifferent_access

    graph_class = 'Kc::MicrosoftTeamsGraph'.safe_constantize
    raise 'KC Teams Chat: MicrosoftTeamsGraph class not found' if graph_class.nil?

    graph = graph_class.new(
      client_id:     options[:client_id],
      client_secret: options[:client_secret],
      tenant_id:     options[:tenant_id],
      access_token:  options[:access_token],
      refresh_token: options[:refresh_token],
    )
    graph.refresh_access_token!

    chat_id = attr[:chat_id]
    raise 'Missing chat_id for Teams Chat delivery' if chat_id.blank?

    body_content = attr[:body] || ''
    content_type = attr[:content_type].to_s.include?('html') ? 'html' : 'text'

    graph.send_chat_message(chat_id, body_content, content_type: content_type)
  end

  private

  def find_or_create_user(message_data)
    email        = message_data[:from_email].to_s.downcase.presence
    display_name = message_data[:from_display_name] || 'Teams User'
    teams_uid    = message_data[:from_user_id]

    # Try to find by Teams authorization first
    if teams_uid.present?
      auth = Authorization.find_by(provider: 'microsoft_teams', uid: teams_uid)
      if auth&.user
        # If we now have a real email and user still has a placeholder, update it
        if email.present? && auth.user.email.to_s.end_with?('@teams.local')
          auth.user.update!(email: email) unless User.where(email: email).where.not(id: auth.user.id).exists?
        end
        return auth.user
      end
    end

    # Try to find by email
    user = email.present? ? User.find_by(email: email) : nil

    if user.nil?
      name_parts = display_name.split(' ', 2)
      user = User.create!(
        firstname:     name_parts[0] || display_name,
        lastname:      name_parts[1] || '',
        email:         email || "teams-#{teams_uid}@teams.local",
        active:        true,
        role_ids:      Role.signup_role_ids,
        updated_by_id: 1,
        created_by_id: 1,
      )
    end

    # Create authorization link if none exists for this Teams user.
    # find_or_create_by block only runs on create (not find), which is the
    # correct behavior: we don't want to re-link an existing authorization
    # to a different user.
    if teams_uid.present?
      Authorization.find_or_create_by(
        provider: 'microsoft_teams',
        uid:      teams_uid,
      ) do |auth|
        auth.user_id  = user.id
        auth.username = display_name
      end
    end

    user
  end

  def find_or_create_ticket(channel, message_data, user)
    conversation_key = build_conversation_key(channel, message_data)
    thread_window    = thread_window_hours(channel)

    # Look for an existing open ticket matching this conversation
    if conversation_key.present?
      existing = find_existing_ticket(conversation_key, thread_window)
      return existing if existing
    end

    # Create new ticket
    group = Group.find_by(id: channel.group_id) || Group.first
    title = build_ticket_title(message_data, user)

    ticket = Ticket.new(
      title:         title,
      group_id:      group.id,
      customer_id:   user.id,
      state_id:      Ticket::State.find_by(default_create: true)&.id || Ticket::State.find_by(name: 'new')&.id,
      priority_id:   Ticket::Priority.find_by(default_create: true)&.id || Ticket::Priority.first&.id,
      preferences:   {
        teams_chat: {
          conversation_key: conversation_key,
          chat_id:          message_data[:chat_id],
          tenant_id:        message_data[:tenant_id],
        },
      },
      updated_by_id: user.id,
      created_by_id: user.id,
    )
    ticket.save!
    ticket
  end

  def create_article(ticket, channel, message_data, user, message_id)
    article_type = Ticket::Article::Type.find_by(name: 'teams_chat_message')
    sender       = Ticket::Article::Sender.find_by(name: 'Customer')

    # Fallback: if the article type migration hasn't run yet, use 'note'
    if article_type.nil?
      Rails.logger.warn 'KC Teams Chat: teams_chat_message article type not found, falling back to note'
      article_type = Ticket::Article::Type.find_by(name: 'note')
    end

    content_type = message_data[:body_content_type] == 'html' ? 'text/html' : 'text/plain'

    article = Ticket::Article.new(
      ticket_id:     ticket.id,
      type_id:       article_type&.id,
      sender_id:     sender&.id,
      from:          message_data[:from_display_name],
      subject:       nil,
      body:          message_data[:body_content] || '',
      content_type:  content_type,
      message_id:    message_id,
      internal:      false,
      preferences:   {
        teams_chat: {
          chat_id:    message_data[:chat_id],
          message_id: message_data[:message_id],
          channel_id: channel.id,
        },
      },
      updated_by_id: user.id,
      created_by_id: user.id,
    )
    article.save!
    article
  end

  def create_agent_article(ticket, channel, message_data, user, message_id)
    article_type = Ticket::Article::Type.find_by(name: 'note') || Ticket::Article::Type.first
    sender       = Ticket::Article::Sender.find_by(name: 'Agent')

    content_type = message_data[:body_content_type] == 'html' ? 'text/html' : 'text/plain'
    body_content = message_data[:body_content] || ''

    # Append label for plain text; for HTML, wrap in a div
    if content_type == 'text/html'
      body_content = "#{body_content}<br><br><em>— Sent via Teams (not through Zammad)</em>"
    else
      body_content = "#{body_content}\n\n— Sent via Teams (not through Zammad)"
    end

    article = Ticket::Article.new(
      ticket_id:     ticket.id,
      type_id:       article_type&.id,
      sender_id:     sender&.id,
      from:          message_data[:from_display_name],
      subject:       nil,
      body:          body_content,
      content_type:  content_type,
      message_id:    message_id,
      internal:      true,
      preferences:   {
        teams_chat: {
          chat_id:          message_data[:chat_id],
          message_id:       message_data[:message_id],
          channel_id:       channel.id,
          outbound_capture: true,
        },
      },
      updated_by_id: user.id,
      created_by_id: user.id,
    )
    article.save!
    article
  end

  def build_ticket_title(message_data, user)
    template = Setting.get('kc_teams_chat_ticket_title_template').to_s.presence || 'Teams Message from {user_name}'
    display_name = message_data[:from_display_name].to_s.presence || user.fullname.presence || 'Unknown'
    title = template.gsub('{user_name}', display_name)
    title.truncate(100, omission: '...')
  end

  def build_conversation_key(channel, message_data)
    tenant_id = message_data[:tenant_id] || channel.options&.dig(:tenant_id)
    chat_id   = message_data[:chat_id]
    "#{tenant_id}:#{chat_id}"
  end

  def find_existing_ticket(conversation_key, thread_window)
    # Sanitize the conversation key for SQL LIKE to prevent wildcard injection
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

    # Only return a ticket if it was updated within the thread window
    cutoff = thread_window.hours.ago
    scope.where('updated_at >= ?', cutoff).first
  end

  def thread_window_hours(channel)
    # Per-channel override takes precedence over global setting
    channel_window = channel.options&.dig(:thread_window_hours)
    return channel_window.to_i if channel_window.present?

    Setting.get('kc_teams_chat_thread_window_hours')&.to_i || 24
  end

end
