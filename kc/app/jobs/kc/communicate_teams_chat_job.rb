# KC: Sends an agent's reply back to a Microsoft Teams chat via Graph API.
#
# Enqueued by the Kc::EnqueueCommunicateTeamsChatJob concern on
# Ticket::Article after_create_commit when the article type is
# 'teams_chat_message' and the sender is 'Agent'.
#
# Safety:
#   - safe_constantize on KC classes
#   - Symbol key access for preferences (Zammad store convention)
#   - Delivery status tracking on both success and final failure
class Kc::CommunicateTeamsChatJob < ApplicationJob
  retry_on StandardError, wait: 10.seconds, attempts: 3

  def perform(article_id)
    article = Ticket::Article.find_by(id: article_id)
    return if article.nil?

    ticket = article.ticket
    return if ticket.nil?

    # Determine which channel and chat to send to.
    # Zammad's `store` serializes with symbol keys.
    chat_prefs    = ticket.preferences&.dig(:teams_chat) || {}
    article_prefs = article.preferences&.dig(:teams_chat) || {}
    chat_id       = article_prefs[:chat_id] || chat_prefs[:chat_id]
    channel_id    = article_prefs[:channel_id] || find_channel_id(ticket)

    if chat_id.blank? || channel_id.blank?
      Rails.logger.warn "KC Teams Chat Job: Missing chat_id or channel_id for article #{article_id}"
      return
    end

    channel = Channel.find_by(id: channel_id, area: 'MicrosoftTeamsChat::Account')
    if channel.nil?
      Rails.logger.warn "KC Teams Chat Job: Channel #{channel_id} not found"
      return
    end

    graph_class = 'Kc::MicrosoftTeamsGraph'.safe_constantize
    if graph_class.nil?
      Rails.logger.error 'KC Teams Chat Job: MicrosoftTeamsGraph class not found'
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

    graph.refresh_access_token!
    persist_tokens(channel, graph)

    # Send the text message
    body_content = article.body || ''
    content_type = article.content_type == 'text/html' ? 'html' : 'text'
    result = graph.send_chat_message(chat_id, body_content, content_type: content_type)

    # Store the returned Graph message ID on the article
    graph_message_id = result['id'] || result[:id]
    if graph_message_id.present?
      article.message_id = "teams_chat:#{graph_message_id}"
      article.preferences[:teams_chat] ||= {}
      article.preferences[:teams_chat][:graph_message_id] = graph_message_id
      article.preferences[:teams_chat][:delivery_status]  = 'sent'
      article.preferences[:teams_chat][:sent_at]          = Time.current.iso8601
      article.save!
    end

    # Send image attachments as separate messages (hostedContents, max 4 MB each)
    send_image_attachments(article, graph, chat_id)

    Rails.logger.info "KC Teams Chat: Sent article #{article_id} to chat #{chat_id}"
  rescue => e
    Rails.logger.error "KC Teams Chat Job: Failed to send article #{article_id}: #{e.message}"

    # Update delivery status on failure (only on final retry)
    if executions >= 3
      begin
        article = Ticket::Article.find_by(id: article_id)
        if article
          article.preferences[:teams_chat] ||= {}
          article.preferences[:teams_chat][:delivery_status] = 'failed'
          article.preferences[:teams_chat][:delivery_error]  = e.message.truncate(500)
          article.save!
        end
      rescue => inner
        Rails.logger.error "KC Teams Chat Job: Failed to update delivery status: #{inner.message}"
      end
    end

    raise
  end

  private

  def find_channel_id(ticket)
    # Look for the most recent inbound article's channel_id
    customer_sender = Ticket::Article::Sender.find_by(name: 'Customer')
    return nil if customer_sender.nil?

    ticket.articles
          .where(sender_id: customer_sender.id)
          .order(created_at: :desc)
          .each do |art|
      channel_id = art.preferences&.dig(:teams_chat, :channel_id)
      return channel_id if channel_id.present?
    end
    nil
  end

  IMAGE_MIME_TYPES = %w[image/png image/jpeg image/gif image/webp image/bmp image/pjpeg].freeze
  MAX_HOSTED_CONTENT_SIZE = 4.megabytes

  def send_image_attachments(article, graph, chat_id)
    image_attachments = article.attachments.select do |att|
      mime = att.preferences['Content-Type'] || att.preferences['Mime-Type'] || ''
      IMAGE_MIME_TYPES.include?(mime.split(';').first&.strip&.downcase)
    end
    return if image_attachments.empty?

    image_attachments.each do |att|
      mime = (att.preferences['Content-Type'] || att.preferences['Mime-Type'] || 'image/png').split(';').first.strip
      content = att.content
      if content.blank?
        Rails.logger.warn "KC Teams Chat: Skipping empty attachment #{att.filename} for article #{article.id}"
        next
      end
      if content.bytesize > MAX_HOSTED_CONTENT_SIZE
        Rails.logger.warn "KC Teams Chat: Skipping attachment #{att.filename} (#{content.bytesize} bytes) — exceeds 4 MB hostedContents limit"
        next
      end

      graph.send_chat_image(chat_id, content, content_type: mime, filename: att.filename)
      Rails.logger.info "KC Teams Chat: Sent image '#{att.filename}' for article #{article.id} to chat #{chat_id}"
    rescue => e
      Rails.logger.error "KC Teams Chat: Failed to send image '#{att.filename}' for article #{article.id}: #{e.message}"
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
    Rails.logger.error "KC Teams Chat Job: Failed to persist tokens: #{e.message}"
  end
end
