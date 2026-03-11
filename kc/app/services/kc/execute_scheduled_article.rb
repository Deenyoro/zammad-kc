# KC: Service object that sends a scheduled article.
#
# Creates a real Ticket::Article from the stored article_data, which
# triggers the standard communication pipeline based on article type:
#   - email              → TicketArticleCommunicateEmailJob (CC, subject supported)
#   - teams_chat_message → Kc::CommunicateTeamsChatJob (routing via ticket.preferences)
#   - ringcentral_sms_message → Kc::CommunicateRingcentralSmsJob (routing via ticket.preferences)
#   - note               → No outbound delivery (internal note)
#
# Safety:
#   - Validates ticket still exists
#   - Validates article_data has required body field
#   - Allowlists article and ticket attribute keys to prevent injection
#   - Wraps article + ticket + status in a database transaction
#   - Enriches article preferences with channel routing from ticket
#   - Validates channel routing exists for Teams/SMS before creating article
#   - Handles attachment transfer from UploadCache
#   - Safe form_id numeric validation
class Kc::ExecuteScheduledArticle

  # Only these keys are permitted from user-submitted article_data.
  ALLOWED_ARTICLE_KEYS = %i[
    body type type_id sender sender_id to cc subject internal
    content_type form_id preferences subtype
  ].freeze

  # Only these keys are permitted from user-submitted ticket_attributes.
  ALLOWED_TICKET_KEYS = %i[
    state_id state priority_id priority owner_id owner
    group_id group pending_time
  ].freeze

  def initialize(scheduled_article)
    raise ArgumentError, 'scheduled_article is required' if scheduled_article.nil?

    @scheduled = scheduled_article
  end

  def execute!
    ticket = Ticket.find_by(id: @scheduled.ticket_id)
    if ticket.nil?
      @scheduled.update!(status: 'failed', error_message: "Ticket ##{@scheduled.ticket_id} no longer exists")
      return
    end

    # Allowlist article keys to prevent attribute injection
    article_params = @scheduled.article_data.deep_symbolize_keys.slice(*ALLOWED_ARTICLE_KEYS)
    form_id        = article_params.delete(:form_id)

    # Validate required body
    if article_params[:body].blank?
      @scheduled.update!(status: 'failed', error_message: 'Article data missing required body field')
      return
    end

    # Ensure required defaults with explicit nil checks
    if article_params[:type_id].blank? && article_params[:type].blank?
      type = Ticket::Article::Type.lookup(name: 'note')
      raise 'Ticket::Article::Type "note" not found' if type.nil?

      article_params[:type_id] = type.id
    end
    if article_params[:sender_id].blank? && article_params[:sender].blank?
      sender = Ticket::Article::Sender.lookup(name: 'Agent')
      raise 'Ticket::Article::Sender "Agent" not found' if sender.nil?

      article_params[:sender_id] = sender.id
    end

    # Enrich article preferences with channel routing info from the ticket.
    # The communication jobs fall back to ticket.preferences, but copying
    # the data onto the article makes each article self-contained and ensures
    # routing even if ticket preferences change between schedule and send.
    enrich_channel_preferences!(article_params, ticket)

    # Validate channel routing exists for non-email outbound types
    validate_channel_routing!(article_params, ticket)

    clean_params = Ticket::Article.association_name_to_id_convert(article_params)
    clean_params = Ticket::Article.param_cleanup(clean_params, true)

    article          = Ticket::Article.new(clean_params)
    article.ticket_id = ticket.id

    # Extract inline base64 images from HTML body BEFORE size check.
    # This must run regardless of form_id — Discord bot articles have no
    # form_id but can contain base64 images from quoted email content.
    attachments = []
    if article.body.present? && article.content_type&.match?(%r{text/html}i)
      article.body, inline_attachments = HtmlSanitizer.replace_inline_images(article.body, ticket.id)
      inline_attachments.each do |att|
        attachments << { data: att[:data], filename: att[:filename], preferences: att[:preferences] }
      end
    end

    # Transfer attachments from UploadCache if form_id was stored
    safe_form_id = validated_form_id(form_id)
    if safe_form_id
      cache = UploadCache.new(safe_form_id)

      # Add cached file attachments (exclude inline images already handled)
      cache.attachments.each do |att|
        next if att.inline?

        attachments << {
          data:        att.content,
          filename:    att.filename,
          preferences: att.preferences,
        }
      end
    end

    article.attachments = attachments if attachments.any?

    # Wrap all state changes in a transaction for atomicity
    ActiveRecord::Base.transaction do
      article.save!

      # Apply ticket attribute changes if specified (allowlisted)
      ticket_attrs = @scheduled.ticket_attributes
      if ticket_attrs.present?
        clean_ticket = ticket_attrs.deep_symbolize_keys.slice(*ALLOWED_TICKET_KEYS)
        clean_ticket = Ticket.association_name_to_id_convert(clean_ticket)
        clean_ticket = Ticket.param_cleanup(clean_ticket, true)
        ticket.update!(clean_ticket) if clean_ticket.present?
      end

      @scheduled.update!(status: 'sent')
    end

    # Best-effort cleanup outside transaction — non-critical
    if safe_form_id
      begin
        UploadCache.new(safe_form_id).destroy
      rescue => e
        Rails.logger.warn "KC: UploadCache cleanup failed for scheduled article ##{@scheduled.id}: #{e.message}"
      end
    end

    Rails.logger.info "KC: Scheduled article ##{@scheduled.id} sent as article ##{article.id} on ticket ##{ticket.id}"
    article
  end

  private

  # Validates form_id is numeric and returns integer, or nil if invalid/blank.
  def validated_form_id(form_id)
    return nil if form_id.blank?
    return nil unless form_id.to_s.match?(/\A\d+\z/)

    form_id.to_i
  end

  # Copies channel routing data from ticket.preferences into article_params[:preferences]
  # so the communication jobs have the routing info directly on the article.
  # This makes the article self-contained and robust against ticket preference changes
  # between schedule time and send time.
  def enrich_channel_preferences!(article_params, ticket)
    article_type_name = resolve_article_type_name(article_params)
    ticket_prefs      = ticket.preferences || {}

    article_params[:preferences] ||= {}

    case article_type_name
    when 'teams_chat_message'
      teams_prefs = ticket_prefs.dig(:teams_chat) || ticket_prefs.dig('teams_chat') || {}
      if teams_prefs.present?
        article_params[:preferences][:teams_chat] ||= {}
        article_params[:preferences][:teams_chat][:chat_id]    ||= teams_prefs[:chat_id] || teams_prefs['chat_id']
        article_params[:preferences][:teams_chat][:channel_id] ||= teams_prefs[:channel_id] || teams_prefs['channel_id']
      end

    when 'ringcentral_sms_message'
      sms_prefs = ticket_prefs.dig(:ringcentral_sms) || ticket_prefs.dig('ringcentral_sms') || {}
      if sms_prefs.present?
        article_params[:preferences][:ringcentral_sms] ||= {}
        # Customer's from_phone becomes our to_phone (we're replying to them)
        article_params[:preferences][:ringcentral_sms][:to_phone]   ||= sms_prefs[:from_phone] || sms_prefs['from_phone']
        article_params[:preferences][:ringcentral_sms][:channel_id] ||= sms_prefs[:channel_id] || sms_prefs['channel_id']
      end
    end
  rescue => e
    Rails.logger.warn "KC: Failed to enrich channel preferences for scheduled article ##{@scheduled.id}: #{e.message}"
  end

  # Validates that required channel routing data exists for outbound channels.
  # Marks as failed if routing data is missing, preventing undeliverable articles.
  def validate_channel_routing!(article_params, ticket)
    article_type_name = resolve_article_type_name(article_params)
    prefs             = article_params[:preferences] || {}
    ticket_prefs      = ticket.preferences || {}

    case article_type_name
    when 'teams_chat_message'
      teams = prefs[:teams_chat] || {}
      ticket_teams = ticket_prefs.dig(:teams_chat) || ticket_prefs.dig('teams_chat') || {}
      chat_id    = teams[:chat_id] || ticket_teams[:chat_id] || ticket_teams['chat_id']
      channel_id = teams[:channel_id] || ticket_teams[:channel_id] || ticket_teams['channel_id']

      if chat_id.blank? || channel_id.blank?
        @scheduled.update!(status: 'failed', error_message: 'Teams Chat routing data (chat_id/channel_id) not found on ticket')
        raise "Teams Chat routing data missing for scheduled article ##{@scheduled.id}"
      end

    when 'ringcentral_sms_message'
      sms = prefs[:ringcentral_sms] || {}
      ticket_sms = ticket_prefs.dig(:ringcentral_sms) || ticket_prefs.dig('ringcentral_sms') || {}
      to_phone   = sms[:to_phone] || ticket_sms[:from_phone] || ticket_sms['from_phone']
      channel_id = sms[:channel_id] || ticket_sms[:channel_id] || ticket_sms['channel_id']

      if to_phone.blank? || channel_id.blank?
        @scheduled.update!(status: 'failed', error_message: 'RingCentral SMS routing data (to_phone/channel_id) not found on ticket')
        raise "RingCentral SMS routing data missing for scheduled article ##{@scheduled.id}"
      end
    end
  end

  # Resolves the article type name from params (could be type name or type_id).
  def resolve_article_type_name(article_params)
    return article_params[:type] if article_params[:type].present?

    type_id = article_params[:type_id]
    return nil if type_id.blank?

    Ticket::Article::Type.lookup(id: type_id)&.name
  end
end
