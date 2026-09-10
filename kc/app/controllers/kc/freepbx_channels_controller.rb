# KC: Admin API controller for the FreePBX phone integration.
#
# A FreePBX channel is just a pointer at the KC PBX connector running on the
# FreePBX host (base URL + bearer token). There is no OAuth: the connector
# is on the local network and authenticates with a shared token.
#
# The index payload also carries the list of numbers the system can text
# from, so the admin pages can offer them as the auto-reply sender for both
# the FreePBX and RingCentral integrations.
class Kc::FreepbxChannelsController < ApplicationController
  include Kc::FreepbxChannelStatus

  prepend_before_action :authenticate_and_authorize!

  CHANNEL_AREA = 'Freepbx::Account'.freeze

  # GET /api/v1/kc/freepbx_channels
  def index
    assets      = {}
    channel_ids = []

    Channel.where(area: CHANNEL_AREA).reorder(:id).each do |channel|
      assets = channel.assets(assets)
      channel_ids.push(channel.id)
    end

    # Every setting the admin page edits lives in this area, including the
    # escalation-call toggle, whose name does not start with kc_freepbx_.
    Setting.where(area: 'Kc::Freepbx').or(Setting.where("name LIKE 'kc_freepbx_%'")).each do |setting|
      assets = setting.assets(assets)
    end

    Group.reorder(:id).each { |group| assets = group.assets(assets) }

    render json: {
      assets:            assets,
      channel_ids:       channel_ids,
      available_numbers: outbound_numbers,
    }
  end

  # POST /api/v1/kc/freepbx_channels
  def create
    base_url = normalize_base_url(params[:base_url])
    if base_url.blank? || params[:token].blank?
      render json: { error: 'Server URL and token are required.' }, status: :unprocessable_content
      return
    end

    if base_url_taken?(base_url)
      render json: { error: 'A FreePBX connection for that server URL already exists.' }, status: :unprocessable_content
      return
    end

    channel = Channel.create!(
      area:          CHANNEL_AREA,
      options:       {
        adapter:  'kc_freepbx',
        base_url: base_url,
        token:    params[:token].to_s,
        label:    params[:label].to_s.presence || 'FreePBX',
      },
      group_id:      params[:group_id].presence&.to_i || Group.first&.id,
      active:        true,
      updated_by_id: current_user.id,
      created_by_id: current_user.id,
    )

    render json: { channel_id: channel.id }
  rescue StandardError => e
    Rails.logger.error "KC FreePBX: Failed to create channel: #{e.message}"
    render json: { error: 'Failed to create the FreePBX connection.' }, status: :unprocessable_content
  end

  # PUT /api/v1/kc/freepbx_channels/:id
  def update
    channel = Channel.find_by!(id: params[:id], area: CHANNEL_AREA)

    new_url = params[:base_url].present? ? normalize_base_url(params[:base_url]) : nil
    if new_url.present? && new_url != channel.options[:base_url].to_s && base_url_taken?(new_url, except: channel.id)
      render json: { error: 'A FreePBX connection for that server URL already exists.' }, status: :unprocessable_content
      return
    end

    channel.with_lock do
      channel.reload
      channel.group_id = params[:group_id].to_i if params[:group_id].present?
      if new_url.present? && new_url != channel.options[:base_url].to_s
        # A different PBX has different CDR ids and a different clock. Start
        # its history from now instead of replaying the old server's marks
        # against it.
        channel.options[:base_url] = new_url
        channel.options.delete(:last_missed_call_poll_at)
        channel.options.delete(:processed_call_ids)
        channel.options.delete(:pending_autoreplies)
      end
      channel.options[:token]    = params[:token].to_s                   if params[:token].present?
      channel.options[:label]    = params[:label].to_s                   if params[:label].present?
      channel.updated_by_id = current_user.id
      channel.save!
    end

    render json: {}
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Connection not found.' }, status: :not_found
  end

  # POST /api/v1/kc/freepbx_channels/:id/test
  # Confirms the connector answers and reports what it can see.
  def test
    channel   = Channel.find_by!(id: params[:id], area: CHANNEL_AREA)
    api_class = 'Kc::FreepbxApi'.safe_constantize
    if api_class.nil?
      render json: { error: 'FreePBX integration not available.' }, status: :unprocessable_content
      return
    end

    api = api_class.for_channel(channel)
    api.health
    extensions = begin
      api.extensions
    rescue StandardError
      []
    end
    recent = begin
      api.calls(since_minutes: 1440, limit: 5).size
    rescue StandardError
      nil
    end

    clear_freepbx_error(channel)

    render json: {
      ok:              true,
      extension_count: extensions.size,
      registered:      extensions.count { |e| e['registered'] || e[:registered] },
      recent_calls:    recent,
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Connection not found.' }, status: :not_found
  rescue StandardError => e
    render json: { ok: false, error: e.message.truncate(200) }, status: :ok
  end

  # POST /api/v1/kc/freepbx_channels/:id/enable
  def enable
    Channel.find_by!(id: params[:id], area: CHANNEL_AREA).update!(active: true)
    render json: {}
  end

  # POST /api/v1/kc/freepbx_channels/:id/disable
  def disable
    Channel.find_by!(id: params[:id], area: CHANNEL_AREA).update!(active: false)
    render json: {}
  end

  # DELETE /api/v1/kc/freepbx_channels/:id
  def destroy
    Channel.find_by!(id: params[:id], area: CHANNEL_AREA).destroy!
    render json: {}
  end

  private

  def outbound_numbers
    sms_class = 'Kc::OutboundSms'.safe_constantize
    return [] if sms_class.nil?

    sms_class.available_numbers
  rescue StandardError => e
    Rails.logger.error "KC FreePBX: Failed to list outbound numbers: #{e.message}"
    []
  end

  def base_url_taken?(url, except: nil)
    scope = Channel.where(area: CHANNEL_AREA)
    scope = scope.where.not(id: except) if except
    scope.any? { |c| c.options.with_indifferent_access[:base_url].to_s.casecmp?(url) }
  end

  def normalize_base_url(value)
    url = value.to_s.strip.chomp('/')
    return '' if url.blank?

    url = "http://#{url}" if !url.match?(%r{\Ahttps?://}i)
    url
  end
end
