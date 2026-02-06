# KC: Settings and Scheduler for proactive API connection health checks.
#
# Creates 4 Settings:
#   - kc_api_health_check_monitored_channels: array of channel IDs to monitor
#   - kc_api_health_check_group_id: group for alert tickets
#   - kc_api_health_check_priority_id: priority for alert tickets
#   - kc_api_health_check_owner_id: owner for alert tickets
#
# Creates 1 Scheduler:
#   - Runs Kc::ApiHealthCheckJob every 5 minutes
#
# Safety:
#   - Idempotent via create_if_not_exists / create_or_update
class AddKcApiHealthCheckSettings < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Setting.create_if_not_exists(
      title:       'KC API Health Check — Monitored Channels',
      name:        'kc_api_health_check_monitored_channels',
      area:        'Kc::ApiHealthCheck',
      description: 'Channel IDs to monitor for API connection health.',
      options:     {},
      state:       [],
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    Setting.create_if_not_exists(
      title:       'KC API Health Check — Alert Group',
      name:        'kc_api_health_check_group_id',
      area:        'Kc::ApiHealthCheck',
      description: 'Group for health check alert tickets. nil defaults to Users group.',
      options:     {},
      state:       nil,
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    Setting.create_if_not_exists(
      title:       'KC API Health Check — Alert Priority',
      name:        'kc_api_health_check_priority_id',
      area:        'Kc::ApiHealthCheck',
      description: 'Priority for health check alert tickets. nil defaults to high.',
      options:     {},
      state:       nil,
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    Setting.create_if_not_exists(
      title:       'KC API Health Check — Alert Owner',
      name:        'kc_api_health_check_owner_id',
      area:        'Kc::ApiHealthCheck',
      description: 'Owner for health check alert tickets. nil = unassigned.',
      options:     {},
      state:       nil,
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    Scheduler.create_if_not_exists(
      name:          'Check KC API connections.',
      method:        'Kc::ApiHealthCheckJob.perform_now',
      period:        5.minutes,
      prio:          4,
      active:        true,
      updated_by_id: 1,
      created_by_id: 1,
      last_run:      Time.current,
    )
  end

  def down
    Scheduler.find_by(name: 'Check KC API connections.')&.destroy
    Setting.find_by(name: 'kc_api_health_check_monitored_channels')&.destroy
    Setting.find_by(name: 'kc_api_health_check_group_id')&.destroy
    Setting.find_by(name: 'kc_api_health_check_priority_id')&.destroy
    Setting.find_by(name: 'kc_api_health_check_owner_id')&.destroy
  end
end
