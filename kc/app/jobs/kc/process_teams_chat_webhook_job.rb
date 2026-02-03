# KC: Processes an inbound Teams chat webhook notification.
#
# Called asynchronously from the webhook controller after clientState
# validation. Fetches the full message from the Graph API and passes
# it to the channel driver's process() method.
#
# Safety:
#   - safe_constantize on KC classes
#   - Defensive nil checks on Graph response fields
#   - Skips system messages
#   - Connected account messages (sent directly in Teams) are captured as internal notes
class Kc::ProcessTeamsChatWebhookJob < ApplicationJob
  retry_on StandardError, wait: 10.seconds, attempts: 3

  def perform(channel_id:, chat_id:, resource:, change_type:, subscription_id:)
    channel = Channel.find_by(id: channel_id, area: 'MicrosoftTeamsChat::Account')
    if channel.nil?
      Rails.logger.warn "KC Teams Job: Channel #{channel_id} not found or not a Teams Chat channel"
      return
    end

    return unless channel.active?

    # Extract message ID from the resource path
    # Resource format: "/chats/{chat-id}/messages/{message-id}"
    message_id = resource.to_s.split('/').last
    if message_id.blank?
      Rails.logger.warn "KC Teams Job: Could not extract message ID from resource: #{resource}"
      return
    end

    graph_class = 'Kc::MicrosoftTeamsGraph'.safe_constantize
    if graph_class.nil?
      Rails.logger.error 'KC Teams Job: MicrosoftTeamsGraph class not found'
      return
    end

    # Fetch full message from Graph API
    opts  = channel.options
    graph = graph_class.new(
      client_id:     opts[:client_id],
      client_secret: opts[:client_secret],
      tenant_id:     opts[:tenant_id],
      access_token:  opts[:access_token],
      refresh_token: opts[:refresh_token],
    )

    begin
      graph.refresh_access_token!
      persist_tokens(channel, graph)
    rescue => e
      Rails.logger.error "KC Teams Job: Token refresh failed: #{e.message}"
      raise
    end

    message = graph.get_chat_message(chat_id, message_id)

    # Skip system/event messages (only process user messages)
    message_type = message['messageType'] || message[:messageType]
    return if message_type != 'message'

    from      = message['from'] || message[:from] || {}
    from_user = from['user'] || from[:user] || {}
    body      = message['body'] || message[:body] || {}

    sender_id = (from_user['id'] || from_user[:id]).to_s

    # Check if sender is the connected account (Zammad service user).
    # DON'T skip these messages — they might be sent directly in Teams
    # (not through Zammad). The driver's dedup check handles Zammad-sent
    # messages via message_id. If the message isn't in Zammad, it was sent
    # directly in Teams and should be captured as an internal note.
    is_connected_account = sender_id.present? && sender_id == opts[:user_id].to_s

    # Fetch chat details to determine if this is a group chat
    chat_type = nil
    chat_topic = nil
    begin
      chat_info = graph.get_chat(chat_id)
      chat_type = chat_info['chatType'] || chat_info[:chatType]
      chat_topic = chat_info['topic'] || chat_info[:topic]
    rescue => e
      Rails.logger.debug { "KC Teams Job: Could not fetch chat details: #{e.message}" }
    end

    message_data = {
      chat_id:           chat_id,
      message_id:        message['id'] || message[:id],
      from_user_id:      from_user['id'] || from_user[:id],
      from_display_name: from_user['displayName'] || from_user[:displayName],
      from_email:        nil, # Will be looked up if needed
      body_content:      body['content'] || body[:content],
      body_content_type: body['contentType'] || body[:contentType],
      created_at:        message['createdDateTime'] || message[:createdDateTime],
      tenant_id:         opts[:tenant_id],
      chat_type:         chat_type,
      chat_topic:        chat_topic,
      attachments:       message['attachments'] || message[:attachments] || [],
      hosted_contents:   message['hostedContents'] || message[:hostedContents] || [],
    }

    # Try to get the sender's email for better user matching
    if message_data[:from_user_id].present?
      begin
        user_info = graph.get_user(message_data[:from_user_id])
        message_data[:from_email] = user_info['mail'] || user_info[:mail] ||
                                         user_info['userPrincipalName'] || user_info[:userPrincipalName]
      rescue => e
        Rails.logger.debug { "KC Teams Job: Could not fetch user email: #{e.message}" }
      end
    end

    # Detect if sender is a Zammad agent/admin by email OR is the connected account
    is_agent = false
    if is_connected_account
      # Messages from the connected account (Zammad service user) sent directly
      # in Teams should be treated as agent messages for context capture.
      is_agent = true
      Rails.logger.info "KC Teams Job: Detected connected account message in chat #{chat_id} — treating as agent for context capture"
    elsif message_data[:from_email].present?
      agent_user = User.find_by(email: message_data[:from_email].downcase)
      is_agent = agent_user.present? && (agent_user.role?('Agent') || agent_user.role?('Admin'))
      if is_agent
        Rails.logger.info "KC Teams Job: Detected agent message from #{message_data[:from_email]} in chat #{chat_id}"
      end
    end
    message_data[:is_agent] = is_agent

    # Process through channel driver (3-arg Zammad convention)
    driver = Channel::Driver::KcMicrosoftTeamsChat.new
    driver.process(opts, message_data, channel)
  end

  private

  def persist_tokens(channel, graph)
    channel.with_lock do
      channel.reload
      channel.options[:access_token]  = graph.access_token
      channel.options[:refresh_token] = graph.refresh_token
      channel.save!
    end
  rescue => e
    Rails.logger.error "KC Teams Job: Failed to persist tokens: #{e.message}"
  end
end
