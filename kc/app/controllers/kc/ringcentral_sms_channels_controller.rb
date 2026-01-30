# KC: Admin API controller for RingCentral SMS channel management.
#
# Provides:
#   - OAuth authorize/callback flow for RingCentral
#   - CRUD operations for SMS channels
#   - Enable/disable channel toggling
#
# All admin endpoints require authentication + admin permission.
#
# Safety:
#   - safe_constantize on KC classes
#   - OAuth state validated with secure_compare
#   - Session params cleaned up after callback
#   - Credentials never sent via GET query string
class Kc::RingcentralSmsChannelsController < ApplicationController
  skip_before_action :verify_csrf_token, only: [:callback]
  prepend_before_action :authenticate_and_authorize!, except: [:callback]

  CHANNEL_AREA = 'RingCentralSms::Account'.freeze

  # GET /api/v1/kc/ringcentral_sms_channels
  # Lists all RingCentral SMS channels with assets.
  def index
    assets      = {}
    channel_ids = []

    Channel.where(area: CHANNEL_AREA).reorder(:id).each do |channel|
      assets = channel.assets(assets)
      channel_ids.push(channel.id)
    end

    # Include KC settings in assets so the frontend Spine collection has them
    # (App.Setting.get/set requires the Setting model to be loaded).
    Setting.where("name LIKE 'kc_ringcentral_sms_%'").each do |setting|
      assets = setting.assets(assets)
    end

    render json: {
      assets:      assets,
      channel_ids: channel_ids,
    }
  end

  # POST /api/v1/kc/ringcentral_sms_channels/authorize
  # Stores OAuth params in session and returns the RingCentral login URL.
  # Credentials are POSTed via AJAX (never in query string).
  def authorize_oauth
    rc_class = 'Kc::RingcentralApi'.safe_constantize
    if rc_class.nil?
      render json: { error: 'RingCentral SMS integration not available' }, status: :unprocessable_entity
      return
    end

    rc = rc_class.new(
      client_id:     params[:client_id],
      client_secret: params[:client_secret],
    )

    state = SecureRandom.hex(24)
    session[:kc_ringcentral_sms_oauth_state] = state
    session[:kc_ringcentral_sms_oauth_user_id] = current_user.id
    session[:kc_ringcentral_sms_oauth_params] = {
      client_id:           params[:client_id],
      client_secret:       params[:client_secret],
      group_id:            params[:group_id],
      thread_window_hours: params[:thread_window_hours],
    }

    url = rc.authorize_url(callback_url, state)
    render json: { authorize_url: url }
  end

  # GET/POST /api/v1/kc/ringcentral_sms_channels/callback
  # Handles the OAuth2 callback from RingCentral.
  # No auth — validated by OAuth state parameter stored in session.
  def callback
    if params[:error].present?
      Rails.logger.error "KC RingCentral SMS OAuth error: #{params[:error_description] || params[:error]}"
      render_callback_error
      return
    end

    state = params[:state].to_s
    saved_state = session[:kc_ringcentral_sms_oauth_state].to_s
    if saved_state.blank? || !ActiveSupport::SecurityUtils.secure_compare(state, saved_state)
      render_callback_error
      return
    end

    saved_params  = (session[:kc_ringcentral_sms_oauth_params] || {}).with_indifferent_access
    saved_user_id = session[:kc_ringcentral_sms_oauth_user_id] || 1
    session.delete(:kc_ringcentral_sms_oauth_state)
    session.delete(:kc_ringcentral_sms_oauth_params)
    session.delete(:kc_ringcentral_sms_oauth_user_id)

    rc_class = 'Kc::RingcentralApi'.safe_constantize
    if rc_class.nil?
      render_callback_error
      return
    end

    rc = rc_class.new(
      client_id:     saved_params[:client_id],
      client_secret: saved_params[:client_secret],
    )

    rc.exchange_code(params[:code], callback_url)

    # Fetch extension info and SMS-capable phone number
    ext_info     = rc.extension_info
    phone_result = rc.phone_numbers
    phone_records = phone_result['records'] || phone_result[:records] || []

    # Find the first SMS-capable phone number
    sms_phone = phone_records.find do |p|
      features = p['features'] || p[:features] || []
      features.include?('SmsSender') || features.include?('MmsSender')
    end

    phone_number = sms_phone && (sms_phone['phoneNumber'] || sms_phone[:phoneNumber])
    if phone_number.blank?
      Rails.logger.error 'KC RingCentral SMS: No SMS-capable phone number found on this extension'
      render_callback_error('No SMS-capable phone number found on this RingCentral extension.')
      return
    end

    user_display_name = ext_info['name'] || ext_info[:name] || ''
    user_email        = ext_info.dig('contact', 'email') || ext_info.dig(:contact, :email) || ''
    extension_id      = ext_info['id'] || ext_info[:id]

    channel = Channel.create!(
      area:    CHANNEL_AREA,
      options: {
        adapter:             'kc_ringcentral_sms',
        client_id:           saved_params[:client_id],
        client_secret:       saved_params[:client_secret],
        access_token:        rc.access_token,
        refresh_token:       rc.refresh_token,
        phone_number:        phone_number,
        user_display_name:   user_display_name,
        user_email:          user_email,
        extension_id:        extension_id.to_s,
        thread_window_hours: saved_params[:thread_window_hours],
      },
      group_id:      saved_params[:group_id].presence&.to_i || Group.first&.id,
      active:        true,
      updated_by_id: saved_user_id,
      created_by_id: saved_user_id,
    )

    # Create webhook subscription for instant SMS notifications
    manager_class = 'Kc::RingcentralSubscriptionManager'.safe_constantize
    if manager_class
      begin
        manager_class.new(channel).ensure_subscription
      rescue => e
        Rails.logger.warn "KC RingCentral SMS: Subscription creation failed (polling fallback active): #{e.message}"
      end
    end

    render_callback_success
  rescue => e
    Rails.logger.error "KC RingCentral SMS OAuth callback failed: #{e.message}"
    render_callback_error
  end

  # PUT /api/v1/kc/ringcentral_sms_channels/:id
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

  # POST /api/v1/kc/ringcentral_sms_channels/:id/enable
  def enable
    channel = Channel.find_by!(id: params[:id], area: CHANNEL_AREA)
    channel.update!(active: true)
    render json: {}
  end

  # POST /api/v1/kc/ringcentral_sms_channels/:id/disable
  def disable
    channel = Channel.find_by!(id: params[:id], area: CHANNEL_AREA)
    channel.update!(active: false)
    render json: {}
  end

  # DELETE /api/v1/kc/ringcentral_sms_channels/:id
  def destroy
    channel = Channel.find_by!(id: params[:id], area: CHANNEL_AREA)

    # Clean up RingCentral subscriptions
    manager_class = 'Kc::RingcentralSubscriptionManager'.safe_constantize
    if manager_class
      begin
        manager_class.new(channel).cleanup_channel_subscriptions
      rescue => e
        Rails.logger.warn "KC RingCentral: Subscription cleanup failed on channel delete: #{e.message}"
      end
    end

    channel.destroy!
    render json: {}
  end

  private

  def callback_url
    fqdn      = Setting.get('fqdn')
    http_type = Setting.get('http_type') || 'https'
    "#{http_type}://#{fqdn}/api/v1/kc/ringcentral_sms_channels/callback"
  end

  def admin_ringcentral_sms_url
    fqdn      = Setting.get('fqdn')
    http_type = Setting.get('http_type') || 'https'
    "#{http_type}://#{fqdn}/#kc_extensions/kc_ringcentral_sms"
  end

  def render_callback_success
    redirect_to admin_ringcentral_sms_url, allow_other_host: true
  end

  def render_callback_error(message = nil)
    escaped_url = ERB::Util.html_escape(admin_ringcentral_sms_url)
    error_text = message || 'Authorization failed. Please check your RingCentral credentials and try again.'
    render html: "<html><body><h2>OAuth Error</h2><p>#{ERB::Util.html_escape(error_text)}</p><p><a href=\"#{escaped_url}\">Back to RingCentral SMS settings</a></p></body></html>".html_safe, layout: false, status: :unprocessable_entity
  end
end
