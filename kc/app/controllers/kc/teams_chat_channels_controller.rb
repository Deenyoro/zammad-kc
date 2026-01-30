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

    render json: {
      assets:      assets,
      channel_ids: channel_ids,
    }
  end

  # GET /api/v1/kc/teams_chat_channels/authorize_oauth
  # Initiates the OAuth2 flow — returns the Microsoft login URL.
  def authorize_oauth
    graph_class = 'Kc::MicrosoftTeamsGraph'.safe_constantize
    if graph_class.nil?
      render json: { error: 'Teams Chat integration not available' }, status: :service_unavailable
      return
    end

    graph = graph_class.new(
      client_id:     params[:client_id],
      client_secret: params[:client_secret],
      tenant_id:     params[:tenant_id],
    )

    state = SecureRandom.hex(24)
    session[:kc_teams_chat_oauth_state] = state
    session[:kc_teams_chat_oauth_params] = {
      client_id:           params[:client_id],
      client_secret:       params[:client_secret],
      tenant_id:           params[:tenant_id],
      group_id:            params[:group_id],
      thread_window_hours: params[:thread_window_hours],
    }

    url = graph.authorize_url(callback_url, state)

    render json: { authorize_url: url }
  end

  # GET/POST /api/v1/kc/teams_chat_channels/callback
  # Handles the OAuth2 callback from Microsoft (form_post mode).
  # No auth — validated by OAuth state parameter stored in session.
  # Renders HTML that closes the popup and refreshes the parent window.
  def callback
    if params[:error].present?
      render_callback_error(params[:error_description] || params[:error])
      return
    end

    state = params[:state].to_s
    saved_state = session[:kc_teams_chat_oauth_state].to_s
    if saved_state.blank? || !ActiveSupport::SecurityUtils.secure_compare(state, saved_state)
      render_callback_error('Invalid OAuth state')
      return
    end

    saved_params = (session[:kc_teams_chat_oauth_params] || {}).with_indifferent_access
    session.delete(:kc_teams_chat_oauth_state)
    session.delete(:kc_teams_chat_oauth_params)

    graph_class = 'Kc::MicrosoftTeamsGraph'.safe_constantize
    if graph_class.nil?
      render_callback_error('Teams Chat integration not available')
      return
    end

    graph = graph_class.new(
      client_id:     saved_params[:client_id],
      client_secret: saved_params[:client_secret],
      tenant_id:     saved_params[:tenant_id],
    )

    graph.exchange_code(params[:code], callback_url)
    user_info = graph.me

    Channel.create!(
      area:    CHANNEL_AREA,
      options: {
        adapter:             'kc_microsoft_teams_chat',
        client_id:           saved_params[:client_id],
        client_secret:       saved_params[:client_secret],
        tenant_id:           saved_params[:tenant_id],
        access_token:        graph.access_token,
        refresh_token:       graph.refresh_token,
        user_display_name:   user_info['displayName'] || user_info[:displayName],
        user_email:          user_info['mail'] || user_info['userPrincipalName'] || user_info[:mail],
        user_id:             user_info['id'] || user_info[:id],
        thread_window_hours: saved_params[:thread_window_hours],
      },
      group_id:      saved_params[:group_id].presence&.to_i || Group.first&.id,
      active:        true,
      updated_by_id: 1,
      created_by_id: 1,
    )

    render_callback_success
  rescue => e
    Rails.logger.error "KC Teams Chat OAuth callback failed: #{e.message}"
    render_callback_error(e.message)
  end

  # PUT /api/v1/kc/teams_chat_channels/:id
  def update
    channel = Channel.find_by!(id: params[:id], area: CHANNEL_AREA)

    if params[:group_id].present?
      channel.group_id = params[:group_id]
    end

    if params[:thread_window_hours].present?
      channel.options[:thread_window_hours] = params[:thread_window_hours].to_i
    end

    channel.save!
    render json: channel
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

  def render_callback_success
    render html: '<html><body><script>window.opener && window.opener.location.reload(); window.close();</script><p>Success! This window will close automatically.</p></body></html>'.html_safe, layout: false
  end

  def render_callback_error(message)
    escaped = ERB::Util.html_escape(message)
    render html: "<html><body><h2>OAuth Error</h2><p>#{escaped}</p><p><a href=\"javascript:window.close()\">Close this window</a></p></body></html>".html_safe, layout: false, status: :unprocessable_entity
  end
end
