# KC: Backup polling job for Teams chat messages.
#
# Runs every 15 minutes via Scheduler. Polls recent messages from each
# active chat subscription to catch any messages that were missed by
# the webhook pathway (e.g. during subscription gaps, Graph outages,
# or notification delivery failures).
#
# Uses the channel driver's process() method which deduplicates by
# Graph message ID, so re-processing already-seen messages is safe.
#
# Safety:
#   - safe_constantize on KC classes
#   - Per-channel rescue so one broken channel doesn't stop the others
#   - Skips own outbound messages
#   - Guards on missing subscription table
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

    sub_class = 'Kc::TeamsSubscription'.safe_constantize
    if sub_class.nil? || !sub_class.table_exists?
      Rails.logger.warn 'KC Teams Poll: Kc::TeamsSubscription not available — skipping'
      return
    end

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
      Rails.logger.error "KC Teams Poll: Token refresh failed for channel #{channel.id}: #{e.message}"
      return
    end

    # Poll messages from each subscribed chat
    subscriptions = sub_class.where(channel: channel)
    subscriptions.find_each do |sub|
      poll_chat(channel, graph, sub.chat_id, opts[:tenant_id])
    rescue => e
      Rails.logger.error "KC Teams Poll: Failed for chat #{sub.chat_id}: #{e.message}"
    end
  end

  def poll_chat(channel, graph, chat_id, tenant_id)
    result = graph.list_chat_messages(chat_id, top: 20)
    messages = result['value'] || result[:value] || []

    driver = Channel::Driver::KcMicrosoftTeamsChat.new

    messages.each do |message|
      # Only process user messages (not system/event messages)
      message_type = message['messageType'] || message[:messageType]
      next if message_type != 'message'

      from      = message['from'] || message[:from] || {}
      from_user = from['user'] || from[:user] || {}
      body      = message['body'] || message[:body] || {}

      # Skip messages sent by the bot user (our own outbound messages)
      sender_id = (from_user['id'] || from_user[:id]).to_s
      next if sender_id.present? && sender_id == channel.options[:user_id].to_s

      # Look up sender email via Graph API (same as webhook job)
      sender_email = nil
      if sender_id.present?
        begin
          user_info = graph.get_user(sender_id)
          sender_email = user_info['mail'] || user_info[:mail] ||
                         user_info['userPrincipalName'] || user_info[:userPrincipalName]
        rescue => e
          Rails.logger.debug "KC Teams Poll: Could not fetch user #{sender_id}: #{e.message}"
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
        created_at:        message['createdDateTime'] || message[:createdDateTime],
        tenant_id:         tenant_id,
      }

      # process() handles dedup internally via message_id
      # 3-arg Zammad convention: (adapter_options, params, channel)
      driver.process(channel.options, message_data, channel)
    rescue => e
      msg_id = (message['id'] || message[:id]) rescue 'unknown'
      Rails.logger.error "KC Teams Poll: Failed to process message #{msg_id}: #{e.message}"
    end
  end

  def persist_tokens(channel, graph)
    channel.options[:access_token]  = graph.access_token
    channel.options[:refresh_token] = graph.refresh_token
    channel.save!
  rescue => e
    Rails.logger.error "KC Teams Poll: Failed to persist tokens: #{e.message}"
  end
end
