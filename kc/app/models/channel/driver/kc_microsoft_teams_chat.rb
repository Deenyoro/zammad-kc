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
        Rails.logger.info "KC Teams Chat: Skipping agent message #{message_data[:message_id]} — no matching ticket for conversation_key #{conversation_key}"
        return nil
      end

      Rails.logger.info "KC Teams Chat: Creating agent note for message #{message_data[:message_id]} in ticket #{ticket.id} from #{message_data[:from_email]}"

      # Update group chat ticket title if needed
      maybe_update_group_chat_title(ticket, message_data)

      transaction_class.execute(reset_user_id: true, context: 'teams_chat') do
        user = find_or_create_user(message_data)
        UserInfo.current_user_id = user.id
        article = create_agent_article(ticket, channel, message_data, user, message_id)
        download_and_attach_files(article, channel, message_data)
        { ticket: ticket, article: article }
      end
    else
      transaction_class.execute(reset_user_id: true, context: 'teams_chat') do
        user   = find_or_create_user(message_data)
        ticket = find_or_create_ticket(channel, message_data, user)
        UserInfo.current_user_id = user.id

        # Update group chat ticket title if needed (for existing tickets)
        maybe_update_group_chat_title(ticket, message_data)

        article = create_article(ticket, channel, message_data, user, message_id)
        download_and_attach_files(article, channel, message_data)
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
  def deliver(options, attr, _notification = false, channel: nil)
    return if Setting.get('import_mode')

    attr = attr.with_indifferent_access

    graph_class = 'Kc::MicrosoftTeamsGraph'.safe_constantize
    raise 'KC Teams Chat: MicrosoftTeamsGraph class not found' if graph_class.nil?

    # Look up channel if not passed (e.g. when called from Zammad's Channel#deliver)
    if channel.nil?
      channel = Channel.find_by(area: 'MicrosoftTeamsChat::Account', active: true)
      raise 'KC Teams Chat: No Teams Chat channel found' if channel.nil?
    end

    graph = graph_class.with_channel_tokens(channel)

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

    # Backdate ticket to original message time so it reflects when the conversation started
    original_time = message_data[:created_at].present? ? Time.zone.parse(message_data[:created_at].to_s) : nil
    if original_time
      ticket.update_columns(created_at: original_time)
    end

    ticket
  end

  def create_article(ticket, channel, message_data, user, message_id)
    article_type = Ticket::Article::Type.find_by(name: 'teams_chat_message')
    sender       = Ticket::Article::Sender.find_by(name: 'Customer') || Ticket::Article::Sender.first

    # Fallback: if the article type migration hasn't run yet, use 'note'
    if article_type.nil?
      Rails.logger.warn 'KC Teams Chat: teams_chat_message article type not found, falling back to note'
      article_type = Ticket::Article::Type.find_by(name: 'note') || Ticket::Article::Type.first
    end

    content_type = message_data[:body_content_type] == 'html' ? 'text/html' : 'text/plain'

    # Use the original Teams message timestamp, not the poll time
    original_time = message_data[:created_at].present? ? Time.zone.parse(message_data[:created_at].to_s) : nil

    article = Ticket::Article.new(
      ticket_id:     ticket.id,
      type_id:       article_type&.id,
      sender_id:     sender&.id,
      from:          message_data[:from_display_name],
      subject:       nil,
      body:          sanitize_teams_body(message_data[:body_content], message_data[:attachments]),
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

    # Backdate to original message time so ticket timeline is accurate
    if original_time
      article.update_columns(created_at: original_time, updated_at: original_time)
    end
    article
  end

  def create_agent_article(ticket, channel, message_data, user, message_id)
    article_type = Ticket::Article::Type.find_by(name: 'note') || Ticket::Article::Type.first
    sender       = Ticket::Article::Sender.find_by(name: 'Agent') || Ticket::Article::Sender.first

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

    # Backdate to original message time
    original_time = message_data[:created_at].present? ? Time.zone.parse(message_data[:created_at].to_s) : nil
    if original_time
      article.update_columns(created_at: original_time, updated_at: original_time)
    end

    article
  end

  IMAGE_MIME_TYPES = %w[image/png image/jpeg image/gif image/webp image/bmp image/pjpeg].freeze
  MAX_ATTACHMENT_BYTES = 25 * 1024 * 1024 # 25 MB per file

  # Downloads inline images (hostedContents) and file attachments from a
  # Teams message and stores them on the Zammad article.
  def download_and_attach_files(article, channel, message_data)
    graph = build_graph_client(channel)
    return if graph.nil?

    chat_id    = message_data[:chat_id]
    message_id = message_data[:message_id]

    # 1. Inline images — extract hostedContents IDs from the HTML body
    body_html = message_data[:body_content].to_s
    hosted_ids = body_html.scan(%r{hostedContents/([^/]+)/\$value}i).flatten.uniq
    hosted_ids.each_with_index do |hc_id, idx|
      data = graph.get_hosted_content(chat_id, message_id, hc_id)
      next if data.blank?
      if data.bytesize > MAX_ATTACHMENT_BYTES
        Rails.logger.warn "KC Teams Chat: Skipping oversized hosted content #{hc_id} (#{data.bytesize} bytes)"
        next
      end

      # Determine content type from the body img tag or default to png
      content_type = detect_hosted_content_type(body_html, hc_id) || 'image/png'
      ext = content_type.split('/').last.sub('jpeg', 'jpg')
      filename = "teams_image_#{idx + 1}.#{ext}"

      Store.create!(
        object:      'Ticket::Article',
        o_id:        article.id,
        data:        data,
        filename:    filename,
        preferences: { 'Content-Type' => content_type },
      )
    rescue => e
      Rails.logger.error "KC Teams Chat: Failed to download hosted content #{hc_id}: #{e.message}"
    end

    # 2. File attachments — referenced in message['attachments']
    #    Teams file uploads have contentType "reference" with a SharePoint contentUrl.
    #    Download via Graph's sharing API (encodes the URL as a sharing token).
    attachments = Array(message_data[:attachments])
    attachments.each do |att|
      att = att.with_indifferent_access
      content_url = att[:contentUrl]
      next if content_url.blank?

      filename = att[:name].presence || "attachment_#{att[:id]}"
      content_type_att = att[:contentType].to_s

      begin
        if content_type_att.include?('reference')
          # SharePoint file upload — download via Graph sharing API
          data = download_sharepoint_file(graph, content_url)
          next if data.blank?

          mime = mime_from_filename(filename)
        else
          next if content_type_att.blank?
          response = UserAgent.get(
            content_url,
            {},
            {
              headers:       { 'Authorization' => "Bearer #{graph.access_token}" },
              open_timeout:  10,
              read_timeout:  30,
              total_timeout: 60,
              log:           { facility: 'kc_teams_graph' },
            },
          )
          next unless response.success?

          data = response.body
          mime = content_type_att
        end

        if data.bytesize > MAX_ATTACHMENT_BYTES
          Rails.logger.warn "KC Teams Chat: Skipping oversized attachment #{filename} (#{data.bytesize} bytes)"
          next
        end

        Store.create!(
          object:      'Ticket::Article',
          o_id:        article.id,
          data:        data,
          filename:    filename,
          preferences: { 'Content-Type' => mime },
        )
      rescue => e
        Rails.logger.error "KC Teams Chat: Failed to download attachment #{filename}: #{e.message}"
      end
    end
  end

  def build_graph_client(channel)
    graph_class = 'Kc::MicrosoftTeamsGraph'.safe_constantize
    return nil if graph_class.nil?

    # Use atomic token refresh — tokens are already fresh from the caller's
    # with_channel_tokens call, so this will typically skip the refresh.
    graph_class.with_channel_tokens(channel)
  rescue => e
    Rails.logger.error "KC Teams Chat: Failed to build graph client for attachment download: #{e.message}"
    nil
  end

  # Downloads a file from SharePoint via the Graph sharing API.
  # Encodes the SharePoint URL as a sharing token and fetches the file content.
  def download_sharepoint_file(graph, sharepoint_url)
    # Encode URL as a Graph sharing token: "u!" + base64url(url)
    encoded = 'u!' + Base64.urlsafe_encode64(sharepoint_url).chomp('=')
    download_url = "https://graph.microsoft.com/v1.0/shares/#{encoded}/driveItem/content"

    response = UserAgent.get(
      download_url,
      {},
      {
        headers:       { 'Authorization' => "Bearer #{graph.access_token}" },
        open_timeout:  10,
        read_timeout:  60,
        total_timeout: 120,
        log:           { facility: 'kc_teams_graph' },
      },
    )

    unless response.success?
      Rails.logger.error "KC Teams Chat: SharePoint download failed (#{response.code}) for #{sharepoint_url}"
      return nil
    end

    response.body
  end

  MIME_EXTENSIONS = {
    'png' => 'image/png', 'jpg' => 'image/jpeg', 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif', 'webp' => 'image/webp', 'bmp' => 'image/bmp',
    'svg' => 'image/svg+xml', 'pdf' => 'application/pdf',
    'doc' => 'application/msword', 'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel', 'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt' => 'application/vnd.ms-powerpoint', 'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'txt' => 'text/plain', 'csv' => 'text/csv', 'zip' => 'application/zip',
    'mp4' => 'video/mp4', 'mp3' => 'audio/mpeg',
  }.freeze

  def mime_from_filename(filename)
    ext = File.extname(filename.to_s).delete('.').downcase
    MIME_EXTENSIONS[ext] || 'application/octet-stream'
  end

  def detect_hosted_content_type(body_html, hc_id)
    # Try to find a data-content-type or similar attribute near the hostedContents reference
    # Graph typically uses image/png or image/jpeg for inline images
    if body_html.include?("#{hc_id}")
      return 'image/gif' if body_html =~ /#{Regexp.escape(hc_id)}[^>]*\.gif/i
      return 'image/jpeg' if body_html =~ /#{Regexp.escape(hc_id)}[^>]*\.jpe?g/i
      return 'image/webp' if body_html =~ /#{Regexp.escape(hc_id)}[^>]*\.webp/i
    end
    nil # default handled by caller
  end

  def build_ticket_title(message_data, user)
    template = Setting.get('kc_teams_chat_ticket_title_template').to_s.presence || 'Teams Message from {user_name}'

    display_name = group_chat_display_name(message_data) ||
                   message_data[:from_display_name].to_s.presence ||
                   user.fullname.presence ||
                   'Unknown'

    title = template.gsub('{user_name}', display_name)
    title.truncate(100, omission: '...')
  end

  # Returns a display name for group chats, or nil for 1:1 chats.
  # Handles edge cases:
  #   - Topic is present and reasonable length: use topic
  #   - Topic is too long (>50 chars): truncate it
  #   - Topic is missing/blank: use "Group Chat #<short_id>"
  #   - Topic looks auto-generated (comma-separated names): use "Group Chat #<short_id>"
  def group_chat_display_name(message_data)
    chat_type = message_data[:chat_type].to_s
    return nil unless chat_type == 'group'

    chat_topic = message_data[:chat_topic].to_s.strip
    chat_id = message_data[:chat_id].to_s

    # Generate a short ID from the chat_id (last 8 chars, or hash if weird format)
    short_id = if chat_id.length >= 8
                 chat_id[-8..-1]
               else
                 Digest::SHA256.hexdigest(chat_id)[0..7]
               end

    # If topic is blank or looks auto-generated (multiple names separated by commas),
    # fall back to "Group Chat #<short_id>"
    if chat_topic.blank? || chat_topic.count(',') >= 2
      return "Group Chat ##{short_id}"
    end

    # Truncate long topics
    if chat_topic.length > 50
      return chat_topic.truncate(50, omission: '...')
    end

    chat_topic
  end

  # Updates an existing ticket's title if it's a group chat and the title is wrong.
  # Called when processing messages for existing tickets.
  def maybe_update_group_chat_title(ticket, message_data)
    return unless message_data[:chat_type].to_s == 'group'

    expected_name = group_chat_display_name(message_data)
    return if expected_name.blank?

    template = Setting.get('kc_teams_chat_ticket_title_template').to_s.presence || 'Teams Message from {user_name}'
    expected_title = template.gsub('{user_name}', expected_name).truncate(100, omission: '...')

    # Only update if the title is different
    current_title = ticket.title.to_s
    return if current_title == expected_title

    # Update the ticket title
    ticket.update!(title: expected_title)
    Rails.logger.info "KC Teams Chat: Updated ticket #{ticket.id} title from '#{current_title}' to '#{expected_title}'"
  rescue => e
    Rails.logger.warn "KC Teams Chat: Failed to update ticket #{ticket.id} title: #{e.message}"
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

  # Strips HTML attachment tags from the body and ensures a non-empty body
  # for Zammad's article validation. When a Teams user sends only an image/file,
  # the body is just an <attachment> tag which has no visible text.
  def sanitize_teams_body(body_content, attachments)
    text = body_content.to_s
    # Remove <attachment> placeholder tags that Teams uses for file references
    cleaned = text.gsub(/<attachment[^>]*>.*?<\/attachment>/mi, '').strip
    return cleaned if cleaned.present?

    # Body was empty or only contained attachment tags — use a placeholder
    has_attachments = Array(attachments).any? { |a| a.is_a?(Hash) }
    has_attachments ? '(attachment)' : '-'
  end

end
