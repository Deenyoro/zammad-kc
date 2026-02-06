# KC: Admin API controller for API connection health check configuration.
#
# Provides:
#   - GET  index:     lists all active channels across monitored areas + current settings
#   - PUT  update:    saves monitored channel IDs and ticket configuration
#   - POST check_now: triggers an immediate health check run
#
# All endpoints require admin permission.
class Kc::ApiHealthCheckController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  MONITORED_AREAS = %w[
    MicrosoftGraph::Account
    MicrosoftTeamsChat::Account
    RingCentralSms::Account
  ].freeze

  AREA_LABELS = {
    'MicrosoftGraph::Account'      => 'Microsoft Graph Email',
    'MicrosoftTeamsChat::Account'   => 'Teams Chat',
    'RingCentralSms::Account'       => 'RingCentral SMS',
  }.freeze

  # GET /api/v1/kc/api_health_check
  def index
    assets = {}

    # Collect all active channels across all monitored areas
    channels_data = []
    MONITORED_AREAS.each do |area|
      Channel.where(area: area, active: true).reorder(:id).each do |channel|
        assets = channel.assets(assets)
        channels_data.push(
          id:           channel.id,
          area:         channel.area,
          area_label:   AREA_LABELS[channel.area] || channel.area,
          account_name: channel_display_name(channel),
          active:       channel.active,
        )
      end
    end

    # Include health check settings in assets
    Setting.where("name LIKE 'kc_api_health_check_%'").each do |setting|
      assets = setting.assets(assets)
    end

    # Include groups, priorities, and admin users for dropdown population
    Group.where(active: true).reorder(:name).each do |group|
      assets = group.assets(assets)
    end
    Ticket::Priority.where(active: true).reorder(:name).each do |priority|
      assets = priority.assets(assets)
    end
    User.with_permissions('admin').each do |user|
      assets = user.assets(assets)
    end

    render json: {
      assets:               assets,
      channels:             channels_data,
      monitored_channel_ids: Setting.get('kc_api_health_check_monitored_channels') || [],
      group_id:             Setting.get('kc_api_health_check_group_id'),
      priority_id:          Setting.get('kc_api_health_check_priority_id'),
      owner_id:             Setting.get('kc_api_health_check_owner_id'),
    }
  end

  # PUT /api/v1/kc/api_health_check
  def update
    if params[:monitored_channel_ids].is_a?(Array)
      # Validate that all IDs are real channels in monitored areas
      valid_ids = Channel.where(id: params[:monitored_channel_ids], area: MONITORED_AREAS).pluck(:id)
      Setting.set('kc_api_health_check_monitored_channels', valid_ids)
    end

    Setting.set('kc_api_health_check_group_id', params[:group_id]) if params.key?(:group_id)
    Setting.set('kc_api_health_check_priority_id', params[:priority_id]) if params.key?(:priority_id)
    Setting.set('kc_api_health_check_owner_id', params[:owner_id]) if params.key?(:owner_id)

    render json: { ok: true }
  end

  # POST /api/v1/kc/api_health_check/check_now
  def check_now
    job_class = 'Kc::ApiHealthCheckJob'.safe_constantize
    if job_class.nil?
      render json: { error: 'Health check job not available' }, status: :unprocessable_entity
      return
    end

    job_class.perform_later
    render json: { ok: true, message: 'Health check queued.' }
  end

  private

  def channel_display_name(channel)
    opts = channel.options
    opts[:name] || opts[:user_display_name] || opts[:user_email] || opts.dig(:inbound, :options, :user) || channel.area
  end
end
