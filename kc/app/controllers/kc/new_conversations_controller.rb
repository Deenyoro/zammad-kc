# KC: Controller for initiating new SMS and Teams conversations from Zammad.
#
# Provides endpoints for agents to:
#   - Start a new SMS conversation (creates ticket + sends SMS)
#   - Start a new Teams chat conversation (creates ticket + sends Teams message)
#   - Search Zammad users with phone numbers (for SMS recipient selection)
#   - Search Teams directory contacts (for Teams recipient selection)
#
# All endpoints require ticket.agent permission (see policy).
#
class Kc::NewConversationsController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  # POST /api/v1/kc/conversations/sms
  #
  # Creates a new ticket with an SMS article and sends the message.
  # The EnqueueCommunicateRingcentralSmsJob concern fires automatically
  # on article creation, which triggers the CommunicateRingcentralSmsJob.
  #
  # Params:
  #   phone_number [String] recipient phone number (required)
  #   body         [String] message text (required)
  #   group_id     [Integer] destination group (optional, falls back to channel default)
  #   customer_id  [Integer] existing Zammad user ID (optional)
  def sms
    phone_number = params[:phone_number].to_s.strip
    body         = params[:body].to_s.strip
    group_id     = params[:group_id]
    customer_id  = params[:customer_id]

    if phone_number.blank? || body.blank?
      render json: { error: 'phone_number and body are required' }, status: :unprocessable_entity
      return
    end

    # Find the active RingCentral SMS channel
    channel = Channel.where(area: 'RingCentralSms::Account', active: true).first
    if channel.nil?
      render json: { error: 'No active RingCentral SMS channel configured' }, status: :unprocessable_entity
      return
    end

    rc_class = 'Kc::RingcentralApi'.safe_constantize
    normalized_phone = if rc_class
                         rc_class.normalize_phone(phone_number)
                       else
                         normalize_phone_fallback(phone_number)
                       end

    from_phone = channel.options&.dig(:phone_number)
    if from_phone.blank?
      render json: { error: 'Channel has no phone number configured' }, status: :unprocessable_entity
      return
    end

    # Build conversation key the same way the driver does
    conversation_key = if rc_class
                         rc_class.conversation_key(from_phone, normalized_phone)
                       else
                         [normalize_phone_fallback(from_phone), normalized_phone].compact.sort.join(':')
                       end

    # Resolve or create customer
    user = if customer_id.present?
             User.find_by(id: customer_id)
           end
    user ||= User.find_by(phone: normalized_phone) || User.find_by(mobile: normalized_phone)
    if user.nil?
      user = User.create!(
        firstname:     normalized_phone,
        lastname:      '',
        phone:         normalized_phone,
        active:        true,
        role_ids:      Role.signup_role_ids,
        updated_by_id: 1,
        created_by_id: 1,
      )
    end

    # Determine group
    group = Group.find_by(id: group_id) || Group.find_by(id: channel.group_id) || Group.first

    # Build ticket title
    title_template = Setting.get('kc_ringcentral_sms_ticket_title_template').to_s.presence || 'SMS from {phone}'
    title = title_template.gsub('{phone}', normalized_phone.to_s).truncate(100, omission: '...')

    transaction_class = 'Transaction'.safe_constantize
    if transaction_class.nil?
      render json: { error: 'Internal error: Transaction class not found' }, status: :internal_server_error
      return
    end

    ticket = nil
    transaction_class.execute(reset_user_id: true, context: 'ringcentral_sms') do
      UserInfo.current_user_id = current_user.id

      ticket = Ticket.create!(
        title:         title,
        group_id:      group.id,
        customer_id:   user.id,
        state_id:      Ticket::State.find_by(default_create: true)&.id || Ticket::State.find_by(name: 'new')&.id,
        priority_id:   Ticket::Priority.find_by(default_create: true)&.id || Ticket::Priority.first&.id,
        preferences:   {
          ringcentral_sms: {
            conversation_key: conversation_key,
            from_phone:       normalized_phone,
            to_phone:         normalize_phone_fallback(from_phone),
            channel_id:       channel.id,
          },
        },
        updated_by_id: current_user.id,
        created_by_id: current_user.id,
      )

      article_type = Ticket::Article::Type.find_by(name: 'ringcentral_sms_message') ||
                     Ticket::Article::Type.find_by(name: 'note')
      sender = Ticket::Article::Sender.find_by(name: 'Agent')

      Ticket::Article.create!(
        ticket_id:     ticket.id,
        type_id:       article_type&.id,
        sender_id:     sender&.id,
        from:          from_phone,
        to:            normalized_phone,
        subject:       nil,
        body:          body,
        content_type:  'text/plain',
        internal:      false,
        preferences:   {
          ringcentral_sms: {
            to_phone:   normalized_phone,
            channel_id: channel.id,
          },
        },
        updated_by_id: current_user.id,
        created_by_id: current_user.id,
      )
    end

    render json: { id: ticket.id, number: ticket.number }
  rescue => e
    Rails.logger.error "KC NewConversations#sms failed: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
    render json: { error: e.message }, status: :internal_server_error
  end

  # POST /api/v1/kc/conversations/teams
  #
  # Creates a 1:1 Teams chat, then creates a ticket with a Teams article.
  # The EnqueueCommunicateTeamsChatJob concern fires automatically on
  # article creation, which triggers the CommunicateTeamsChatJob.
  #
  # Params:
  #   teams_user_id [String] Azure AD user ID of the recipient (required)
  #   display_name  [String] recipient's display name (required)
  #   email         [String] recipient's email (optional)
  #   body          [String] message text (required)
  #   group_id      [Integer] destination group (optional)
  def teams
    teams_user_id = params[:teams_user_id].to_s.strip
    display_name  = params[:display_name].to_s.strip
    email         = params[:email].to_s.strip.presence
    body          = params[:body].to_s.strip
    group_id      = params[:group_id]

    if teams_user_id.blank? || display_name.blank? || body.blank?
      render json: { error: 'teams_user_id, display_name, and body are required' }, status: :unprocessable_entity
      return
    end

    # Find the active Teams channel
    channel = Channel.where(area: 'MicrosoftTeamsChat::Account', active: true).first
    if channel.nil?
      render json: { error: 'No active Microsoft Teams channel configured' }, status: :unprocessable_entity
      return
    end

    graph_class = 'Kc::MicrosoftTeamsGraph'.safe_constantize
    if graph_class.nil?
      render json: { error: 'Internal error: MicrosoftTeamsGraph class not found' }, status: :internal_server_error
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

    # Refresh tokens and create/get the 1:1 chat
    graph.refresh_access_token!
    persist_tokens(channel, graph)

    chat_result = graph.create_chat(teams_user_id)
    chat_id = chat_result['id'] || chat_result[:id]
    if chat_id.blank?
      render json: { error: 'Failed to create Teams chat — no chat_id returned' }, status: :internal_server_error
      return
    end

    # Resolve or create customer user (same logic as the Teams driver)
    user = find_or_create_teams_user(teams_user_id, display_name, email)

    # Determine group
    group = Group.find_by(id: group_id) || Group.find_by(id: channel.group_id) || Group.first

    # Build ticket title
    title_template = Setting.get('kc_teams_chat_ticket_title_template').to_s.presence || 'Teams Message from {user_name}'
    title = title_template.gsub('{user_name}', display_name).truncate(100, omission: '...')

    # Build conversation key
    tenant_id = opts[:tenant_id]
    conversation_key = "#{tenant_id}:#{chat_id}"

    transaction_class = 'Transaction'.safe_constantize
    if transaction_class.nil?
      render json: { error: 'Internal error: Transaction class not found' }, status: :internal_server_error
      return
    end

    ticket = nil
    transaction_class.execute(reset_user_id: true, context: 'teams_chat') do
      UserInfo.current_user_id = current_user.id

      ticket = Ticket.create!(
        title:         title,
        group_id:      group.id,
        customer_id:   user.id,
        state_id:      Ticket::State.find_by(default_create: true)&.id || Ticket::State.find_by(name: 'new')&.id,
        priority_id:   Ticket::Priority.find_by(default_create: true)&.id || Ticket::Priority.first&.id,
        preferences:   {
          teams_chat: {
            conversation_key: conversation_key,
            chat_id:          chat_id,
            tenant_id:        tenant_id,
            channel_id:       channel.id,
          },
        },
        updated_by_id: current_user.id,
        created_by_id: current_user.id,
      )

      article_type = Ticket::Article::Type.find_by(name: 'teams_chat_message') ||
                     Ticket::Article::Type.find_by(name: 'note')
      sender = Ticket::Article::Sender.find_by(name: 'Agent')

      Ticket::Article.create!(
        ticket_id:     ticket.id,
        type_id:       article_type&.id,
        sender_id:     sender&.id,
        from:          current_user.fullname,
        subject:       nil,
        body:          body,
        content_type:  'text/plain',
        internal:      false,
        preferences:   {
          teams_chat: {
            chat_id:    chat_id,
            channel_id: channel.id,
          },
        },
        updated_by_id: current_user.id,
        created_by_id: current_user.id,
      )
    end

    render json: { id: ticket.id, number: ticket.number }
  rescue => e
    Rails.logger.error "KC NewConversations#teams failed: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
    render json: { error: e.message }, status: :internal_server_error
  end

  # GET /api/v1/kc/conversations/sms_users?query=...
  #
  # Searches Zammad users by name, phone, or mobile for SMS recipient selection.
  # Returns only users that have a phone or mobile number set.
  def sms_users
    query = params[:query].to_s.strip
    if query.length < 2
      render json: { users: [] }
      return
    end

    sanitized = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    users = User.where(active: true)
                .where('(firstname ILIKE :q OR lastname ILIKE :q OR phone ILIKE :q OR mobile ILIKE :q)', q: sanitized)
                .where('phone IS NOT NULL AND phone != ? OR mobile IS NOT NULL AND mobile != ?', '', '')
                .limit(20)
                .select(:id, :firstname, :lastname, :phone, :mobile)

    render json: {
      users: users.map { |u|
        {
          id:    u.id,
          name:  "#{u.firstname} #{u.lastname}".strip,
          phone: u.phone.presence,
          mobile: u.mobile.presence,
        }
      },
    }
  end

  # GET /api/v1/kc/conversations/teams_contacts?query=...
  #
  # Searches the Microsoft Teams / Azure AD directory for users.
  def teams_contacts
    query = params[:query].to_s.strip
    if query.length < 2
      render json: { contacts: [] }
      return
    end

    channel = Channel.where(area: 'MicrosoftTeamsChat::Account', active: true).first
    if channel.nil?
      render json: { error: 'No active Microsoft Teams channel configured' }, status: :unprocessable_entity
      return
    end

    graph_class = 'Kc::MicrosoftTeamsGraph'.safe_constantize
    if graph_class.nil?
      render json: { error: 'Internal error: MicrosoftTeamsGraph class not found' }, status: :internal_server_error
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

    result   = graph.search_users(query, top: 10)
    contacts = Array(result['value'] || result[:value])

    render json: {
      contacts: contacts.map { |c|
        {
          id:           c['id'] || c[:id],
          display_name: c['displayName'] || c[:displayName],
          email:        c['mail'] || c[:mail],
          job_title:    c['jobTitle'] || c[:jobTitle],
        }
      },
    }
  rescue => e
    Rails.logger.error "KC NewConversations#teams_contacts failed: #{e.message}"
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  def find_or_create_teams_user(teams_user_id, display_name, email)
    # Try to find by Teams authorization first
    if teams_user_id.present?
      auth = Authorization.find_by(provider: 'microsoft_teams', uid: teams_user_id)
      return auth.user if auth&.user
    end

    # Try to find by email
    user = email.present? ? User.find_by(email: email.downcase) : nil

    if user.nil?
      name_parts = display_name.split(' ', 2)
      user = User.create!(
        firstname:     name_parts[0] || display_name,
        lastname:      name_parts[1] || '',
        email:         email || "teams-#{teams_user_id}@teams.local",
        active:        true,
        role_ids:      Role.signup_role_ids,
        updated_by_id: 1,
        created_by_id: 1,
      )
    end

    # Create authorization link
    if teams_user_id.present?
      Authorization.find_or_create_by(
        provider: 'microsoft_teams',
        uid:      teams_user_id,
      ) do |auth|
        auth.user_id  = user.id
        auth.username = display_name
      end
    end

    user
  end

  def persist_tokens(channel, graph)
    channel.with_lock do
      channel.reload
      channel.options[:access_token]  = graph.access_token
      channel.options[:refresh_token] = graph.refresh_token
      channel.save!
    end
  rescue => e
    Rails.logger.error "KC NewConversations: Failed to persist tokens: #{e.message}"
  end

  def normalize_phone_fallback(number)
    return nil if number.blank?

    digits = number.to_s.gsub(/[^\d+]/, '').delete('+')
    case digits.length
    when 10 then "+1#{digits}"
    when 11 then "+#{digits}"
    else "+#{digits}"
    end
  end
end
