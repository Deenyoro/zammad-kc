# KC: Polling job for Teams chat messages.
#
# Runs every 30 seconds via Scheduler. Two modes per cycle:
#   - Active chats (have any open ticket): polled every run
#   - Full discovery (list all chats via Graph API): every 5 minutes
#
# Only processes messages created after the channel was connected, so
# historical messages from before enrollment are never imported.
#
# Safety:
#   - safe_constantize on KC classes
#   - Per-channel rescue so one broken channel doesn't stop the others
#   - Skips own bot messages (Zammad-sent via communicate job)
#   - Detects agent/staff senders by email → creates internal notes
#   - Skips messages older than channel creation time
#   - Deduplicates by Graph message ID
class Kc::PollTeamsChatMessagesJob < ApplicationJob

  def perform
    Channel.where(area: 'MicrosoftTeamsChat::Account', active: true).find_each do |channel|
      poll_channel(channel)
    rescue => e
      Rails.logger.error "KC Teams Poll: Failed for channel #{channel.id}: #{e.message}"
    end
  end

  # Class method called by Scheduler
  def self.perform_now
    new.perform
  end

  private

  def poll_channel(channel)
    graph_class = 'Kc::MicrosoftTeamsGraph'.safe_constantize
    if graph_class.nil?
      Rails.logger.error 'KC Teams Poll: MicrosoftTeamsGraph class not found'
      return
    end

    opts  = channel.options.with_indifferent_access
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
      Rails.logger.error "KC Teams Poll: Token refresh failed for channel #{channel.id}: #{e.message} — " \
                         'ALL polling skipped for this channel until token is fixed. ' \
                         'Reauthenticate the channel in Admin > KC Extensions > Teams Chat.'
      return
    end

    # Cache user email lookups within this poll cycle to avoid rate limits
    @user_email_cache = {}

    # Initialize subscription manager for auto-creating webhooks
    manager_class = 'Kc::TeamsSubscriptionManager'.safe_constantize
    @subscription_manager = manager_class&.new(channel)

    # Always poll chats that have open tickets — no lookback window.
    # Discovery is only needed for finding NEW chats without tickets yet.
    active_chat_ids = active_chat_ids_for(channel)
    active_chat_ids.each do |chat_id|
      poll_chat(channel, graph, chat_id, opts[:tenant_id])
    rescue => e
      Rails.logger.error "KC Teams Poll: Failed for active chat #{chat_id}: #{e.message}"
    end

    # Full discovery via Graph API at configurable interval
    discovery_interval = (Setting.get('kc_teams_chat_discovery_interval_minutes')&.to_i || 5).clamp(1, 60).minutes
    last_discovery = opts[:last_poll_discovery_at]
    if last_discovery.blank? || Time.zone.parse(last_discovery.to_s) < discovery_interval.ago
      discover_and_poll(channel, graph, opts, active_chat_ids)
    end
  end

  # Returns chat_ids that have ANY open ticket — always poll these every cycle.
  def active_chat_ids_for(channel)
    closed_state_ids = Ticket::State
                         .joins(:state_type)
                         .where(ticket_state_types: { name: 'closed' })
                         .select(:id)

    Ticket.where('preferences LIKE ?', '%teams_chat%')
          .where.not(state_id: closed_state_ids)
          .select(:id, :preferences)
          .filter_map { |t| t.preferences.dig('teams_chat', 'chat_id') }
          .uniq
  end

  def discover_and_poll(channel, graph, opts, already_polled_ids)
    total_discovered = 0

    begin
      graph.list_chats(top: 50) do |batch|
        total_discovered += batch.size

        batch.each do |chat|
          chat_id = chat['id'] || chat[:id]
          next if chat_id.blank?
          next if already_polled_ids.include?(chat_id)

          poll_chat(channel, graph, chat_id, opts[:tenant_id])
        rescue => e
          chat_id_safe = (chat['id'] || chat[:id]) rescue 'unknown'
          Rails.logger.error "KC Teams Poll: Failed for discovered chat #{chat_id_safe}: #{e.message}"
        end
      end
    rescue => e
      Rails.logger.error "KC Teams Poll: Failed to list chats for channel #{channel.id}: #{e.message}"
      return
    end

    Rails.logger.info "KC Teams Poll: Discovery found #{total_discovered} chats for channel #{channel.id}"

    # Record discovery time (locked to avoid race with concurrent token persistence)
    channel.with_lock do
      channel.reload
      channel.options[:last_poll_discovery_at] = Time.current.iso8601
      channel.save!
    end
  rescue => e
    Rails.logger.error "KC Teams Poll: Discovery failed for channel #{channel.id}: #{e.message}"
  end

  def poll_chat(channel, graph, chat_id, tenant_id)
    # Automatically create webhook subscription for this chat (if not already exists)
    if @subscription_manager
      begin
        @subscription_manager.ensure_subscription(chat_id)
      rescue => e
        Rails.logger.debug "KC Teams Poll: Failed to ensure subscription for chat #{chat_id}: #{e.message}"
        # Non-critical: continue polling even if webhook creation fails
      end
    end

    result = graph.list_chat_messages(chat_id, top: 20)
    messages = result['value'] || result[:value] || []

    # Determine cutoff date
    # Use poll_cutoff_date if configured (to avoid importing messages from
    # before the addon was deployed). Otherwise use channel creation time.
    opts = channel.options.with_indifferent_access
    cutoff_date = opts[:poll_cutoff_date]
    channel_created_at = if cutoff_date.present?
                           Time.zone.parse(cutoff_date.to_s) rescue channel.created_at
                         else
                           channel.created_at
                         end

    driver = Channel::Driver::KcMicrosoftTeamsChat.new

    messages.each do |message|
      # Only process user messages (not system/event messages)
      message_type = message['messageType'] || message[:messageType]
      next if message_type != 'message'

      # Skip messages from before the channel was created
      msg_created = message['createdDateTime'] || message[:createdDateTime]
      if msg_created.present?
        msg_time = Time.zone.parse(msg_created.to_s) rescue nil
        next if msg_time && msg_time < channel_created_at
      end

      from      = message['from'] || message[:from] || {}
      from_user = from['user'] || from[:user] || {}
      body      = message['body'] || message[:body] || {}

      # Skip messages sent by the bot user (our own outbound messages)
      sender_id = (from_user['id'] || from_user[:id]).to_s
      next if sender_id.present? && sender_id == channel.options[:user_id].to_s

      # Look up sender email via Graph API (cached per poll cycle)
      sender_email = nil
      if sender_id.present?
        if @user_email_cache.key?(sender_id)
          sender_email = @user_email_cache[sender_id]
        else
          begin
            user_info = graph.get_user(sender_id)
            sender_email = user_info['mail'] || user_info[:mail] ||
                           user_info['userPrincipalName'] || user_info[:userPrincipalName]
          rescue => e
            Rails.logger.debug "KC Teams Poll: Could not fetch user #{sender_id}: #{e.message}"
          end
          @user_email_cache[sender_id] = sender_email
        end
      end

      # Detect if sender is a Zammad agent/admin by email
      is_agent = false
      if sender_email.present?
        agent_user = User.find_by(email: sender_email.downcase)
        is_agent = agent_user.present? && (agent_user.role?('Agent') || agent_user.role?('Admin'))
        if is_agent
          Rails.logger.info "KC Teams Poll: Detected agent message from #{sender_email} in chat #{chat_id}"
        end
      end

      message_data = {
        chat_id:           chat_id,
        message_id:        message['id'] || message[:id],
        from_user_id:      sender_id,
        from_display_name: from_user['displayName'] || from_user[:displayName],
        from_email:        sender_email,
        body_content:      body['content'] || body[:content],
        body_content_type: body['contentType'] || body[:contentType],
        created_at:        msg_created,
        tenant_id:         tenant_id,
        is_agent:          is_agent,
        attachments:       message['attachments'] || message[:attachments] || [],
        hosted_contents:   message['hostedContents'] || message[:hostedContents] || [],
      }

      # process() handles dedup internally via message_id
      driver.process(channel.options, message_data, channel)
    rescue => e
      msg_id = (message['id'] || message[:id]) rescue 'unknown'
      Rails.logger.error "KC Teams Poll: Failed to process message #{msg_id}: #{e.message}"
    end
  end

  def persist_tokens(channel, graph)
    channel.with_lock do
      channel.reload
      channel.options[:access_token]  = graph.access_token
      channel.options[:refresh_token] = graph.refresh_token
      channel.save!
    end
  rescue => e
    Rails.logger.error "KC Teams Poll: Failed to persist tokens: #{e.message}"
  end
end
