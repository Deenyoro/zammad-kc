# KC: Admin API controller for Microsoft Teams Chat channel management.
#
# Provides:
#   - OAuth authorize/callback flow for Azure AD
#   - CRUD operations for Teams Chat channels
#   - Enable/disable channel toggling
#
# All admin endpoints require authentication + admin permission.
#
# Safety:
#   - safe_constantize on KC classes
#   - OAuth state validated with secure_compare
#   - Session params cleaned up after callback
#   - Credentials never sent via GET query string
class Kc::TeamsChatChannelsController < ApplicationController
  skip_before_action :verify_csrf_token, only: [:callback]
  prepend_before_action :authenticate_and_authorize!, except: [:callback]

  CHANNEL_AREA = 'MicrosoftTeamsChat::Account'.freeze

  # GET /api/v1/kc/teams_chat_channels
  # Lists all Teams Chat channels with assets.
  def index
    assets      = {}
    channel_ids = []

    Channel.where(area: CHANNEL_AREA).reorder(:id).each do |channel|
      assets = channel.assets(assets)
      channel_ids.push(channel.id)
    end

    # Include KC settings in assets so the frontend Spine collection has them
    # (App.Setting.get/set requires the Setting model to be loaded).
    Setting.where("name LIKE 'kc_teams_chat_%' OR name LIKE 'kc_teams_directory_%'").each do |setting|
      assets = setting.assets(assets)
    end

    render json: {
      assets:      assets,
      channel_ids: channel_ids,
    }
  end

  # POST /api/v1/kc/teams_chat_channels/authorize
  # Stores OAuth params in session and returns the Microsoft login URL.
  # Credentials are POSTed via AJAX (never in query string).
  def authorize_oauth
    graph_class = 'Kc::MicrosoftTeamsGraph'.safe_constantize
    if graph_class.nil?
      render json: { error: 'Teams Chat integration not available' }, status: :unprocessable_entity
      return
    end

    graph = graph_class.new(
      client_id:     params[:client_id],
      client_secret: params[:client_secret],
      tenant_id:     params[:tenant_id],
    )

    state = SecureRandom.hex(24)
    session[:kc_teams_chat_oauth_state] = state
    session[:kc_teams_chat_oauth_user_id] = current_user.id
    session[:kc_teams_chat_oauth_params] = {
      client_id:           params[:client_id],
      client_secret:       params[:client_secret],
      tenant_id:           params[:tenant_id],
      group_id:            params[:group_id],
      thread_window_hours: params[:thread_window_hours],
      poll_cutoff_date:    params[:poll_cutoff_date],
    }

    url = graph.authorize_url(callback_url, state)
    render json: { authorize_url: url }
  end

  # GET/POST /api/v1/kc/teams_chat_channels/callback
  # Handles the OAuth2 callback from Microsoft.
  # No auth — validated by OAuth state parameter stored in session.
  def callback
    if params[:error].present?
      Rails.logger.error "KC Teams Chat OAuth error from Microsoft: #{params[:error_description] || params[:error]}"
      render_callback_error
      return
    end

    state = params[:state].to_s
    saved_state = session[:kc_teams_chat_oauth_state].to_s
    if saved_state.blank? || !ActiveSupport::SecurityUtils.secure_compare(state, saved_state)
      render_callback_error
      return
    end

    saved_params  = (session[:kc_teams_chat_oauth_params] || {}).with_indifferent_access
    saved_user_id = session[:kc_teams_chat_oauth_user_id] || 1
    session.delete(:kc_teams_chat_oauth_state)
    session.delete(:kc_teams_chat_oauth_params)
    session.delete(:kc_teams_chat_oauth_user_id)

    graph_class = 'Kc::MicrosoftTeamsGraph'.safe_constantize
    if graph_class.nil?
      render_callback_error
      return
    end

    graph = graph_class.new(
      client_id:     saved_params[:client_id],
      client_secret: saved_params[:client_secret],
      tenant_id:     saved_params[:tenant_id],
    )

    graph.exchange_code(params[:code], callback_url)
    user_info = graph.me

    if saved_params[:channel_id].present?
      # Reauthentication — update existing channel with fresh tokens
      channel = Channel.find_by!(id: saved_params[:channel_id], area: CHANNEL_AREA)
      channel.with_lock do
        channel.reload
        channel.options[:access_token]      = graph.access_token
        channel.options[:refresh_token]     = graph.refresh_token
        channel.options[:token_refreshed_at] = Time.current.utc.iso8601
        channel.options[:user_display_name] = user_info['displayName'] || user_info[:displayName]
        channel.options[:user_email]        = user_info['mail'] || user_info['userPrincipalName'] || user_info[:mail]
        channel.options[:user_id]           = user_info['id'] || user_info[:id]
        channel.updated_by_id = saved_user_id
        channel.save!
      end
    else
      # New channel creation
      Channel.create!(
        area:    CHANNEL_AREA,
        options: {
          adapter:             'kc_microsoft_teams_chat',
          client_id:           saved_params[:client_id],
          client_secret:       saved_params[:client_secret],
          tenant_id:           saved_params[:tenant_id],
          access_token:        graph.access_token,
          refresh_token:       graph.refresh_token,
          token_refreshed_at:  Time.current.utc.iso8601,
          user_display_name:   user_info['displayName'] || user_info[:displayName],
          user_email:          user_info['mail'] || user_info['userPrincipalName'] || user_info[:mail],
          user_id:             user_info['id'] || user_info[:id],
          thread_window_hours: saved_params[:thread_window_hours],
          poll_cutoff_date:    saved_params[:poll_cutoff_date],
        },
        group_id:      saved_params[:group_id].presence&.to_i || Group.first&.id,
        active:        true,
        updated_by_id: saved_user_id,
        created_by_id: saved_user_id,
      )
    end

    render_callback_success
  rescue => e
    Rails.logger.error "KC Teams Chat OAuth callback failed: #{e.message}"
    render_callback_error
  end

  # PUT /api/v1/kc/teams_chat_channels/:id
  def update
    channel = Channel.find_by!(id: params[:id], area: CHANNEL_AREA)

    channel.with_lock do
      channel.reload

      if params[:group_id].present?
        channel.group_id = params[:group_id]
      end

      if params[:thread_window_hours].present?
        channel.options[:thread_window_hours] = params[:thread_window_hours].to_i
      end

      if params[:poll_cutoff_date].present?
        channel.options[:poll_cutoff_date] = params[:poll_cutoff_date]
      end

      if params.key?(:organization_id)
        channel.options[:organization_id] = params[:organization_id].presence&.to_i
      end

      if params.key?(:directory_sync)
        channel.options[:directory_sync] = ActiveModel::Type::Boolean.new.cast(params[:directory_sync])
      end

      channel.save!
    end

    render json: { id: channel.id, assets: channel.assets({}) }
  end

  # POST /api/v1/kc/teams_chat_channels/:id/sync_directory
  def sync_directory
    channel = Channel.find_by(id: params[:id], area: CHANNEL_AREA)
    if channel.nil?
      render json: { error: 'Channel not found' }, status: :not_found
      return
    end

    Kc::TeamsDirectorySyncJob.perform_later(channel.id)
    render json: { message: 'Directory sync started' }
  end

  # POST /api/v1/kc/teams_chat_channels/:id/reauthenticate
  # Initiates OAuth re-authorization for an existing channel.
  # Uses the channel's stored credentials — no modal needed.
  def reauthenticate
    channel = Channel.find_by!(id: params[:id], area: CHANNEL_AREA)
    options = channel.options.with_indifferent_access

    graph_class = 'Kc::MicrosoftTeamsGraph'.safe_constantize
    if graph_class.nil?
      render json: { error: 'Teams Chat integration not available' }, status: :unprocessable_entity
      return
    end

    graph = graph_class.new(
      client_id:     options[:client_id],
      client_secret: options[:client_secret],
      tenant_id:     options[:tenant_id],
    )

    state = SecureRandom.hex(24)
    session[:kc_teams_chat_oauth_state]   = state
    session[:kc_teams_chat_oauth_user_id] = current_user.id
    session[:kc_teams_chat_oauth_params]  = {
      client_id:           options[:client_id],
      client_secret:       options[:client_secret],
      tenant_id:           options[:tenant_id],
      group_id:            channel.group_id,
      thread_window_hours: options[:thread_window_hours],
      channel_id:          channel.id,
    }

    url = graph.authorize_url(callback_url, state)
    render json: { authorize_url: url }
  end

  # POST /api/v1/kc/teams_chat_channels/:id/enable
  def enable
    channel = Channel.find_by!(id: params[:id], area: CHANNEL_AREA)
    channel.update!(active: true)
    render json: {}
  end

  # POST /api/v1/kc/teams_chat_channels/:id/disable
  def disable
    channel = Channel.find_by!(id: params[:id], area: CHANNEL_AREA)
    channel.update!(active: false)
    render json: {}
  end

  # DELETE /api/v1/kc/teams_chat_channels/:id
  def destroy
    channel = Channel.find_by!(id: params[:id], area: CHANNEL_AREA)

    # Clean up Graph subscriptions
    manager_class = 'Kc::TeamsSubscriptionManager'.safe_constantize
    if manager_class
      begin
        manager_class.new(channel).cleanup_channel_subscriptions
      rescue => e
        Rails.logger.warn "KC Teams: Subscription cleanup failed on channel delete: #{e.message}"
      end
    end

    channel.destroy!
    render json: {}
  end

  private

  def callback_url
    fqdn      = Setting.get('fqdn')
    http_type = Setting.get('http_type') || 'https'
    "#{http_type}://#{fqdn}/api/v1/kc/teams_chat_channels/callback"
  end

  def admin_teams_chat_url
    fqdn      = Setting.get('fqdn')
    http_type = Setting.get('http_type') || 'https'
    "#{http_type}://#{fqdn}/#kc_extensions/kc_teams_chat"
  end

  def render_callback_success
    redirect_to admin_teams_chat_url, allow_other_host: true
  end

  def render_callback_error
    escaped_url = ERB::Util.html_escape(admin_teams_chat_url)
    render html: "<html><body><h2>OAuth Error</h2><p>Authorization failed. Please check your Azure AD credentials and try again.</p><p><a href=\"#{escaped_url}\">Back to Teams Chat settings</a></p></body></html>".html_safe, layout: false, status: :unprocessable_entity
  end
end
