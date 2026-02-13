# frozen_string_literal: true

# KC: Settings and Scheduler for Discord bot health monitoring.
#
# Creates 7 Settings (area: Kc::ApiHealthCheck):
#   - kc_discord_bot_health_check_enabled          — boolean, default false
#   - kc_discord_bot_health_check_url              — string, default http://zammad-discord-bot:3100/healthz
#   - kc_discord_bot_health_check_interval         — integer (seconds), default 30
#   - kc_discord_bot_health_check_failure_threshold — integer, default 4 (4 × 30s = 2 min)
#   - kc_discord_bot_health_check_priority_id      — integer, default nil (falls back to highest)
#   - kc_discord_bot_health_check_group_id         — integer, default nil (falls back to API health check group)
#   - kc_discord_bot_health_check_owner_id         — integer, default nil
#
# Creates 1 Scheduler:
#   - Runs Kc::DiscordBotHealthCheckJob every 30 seconds
#
# Safety:
#   - Idempotent via create_if_not_exists / create_or_update
class AddKcDiscordBotHealthCheck < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Setting.create_if_not_exists(
      title:       'KC Discord Bot Health Check — Enabled',
      name:        'kc_discord_bot_health_check_enabled',
      area:        'Kc::ApiHealthCheck',
      description: 'Enable or disable the Discord bot health check.',
      options:     {},
      state:       false,
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    Setting.create_if_not_exists(
      title:       'KC Discord Bot Health Check — URL',
      name:        'kc_discord_bot_health_check_url',
      area:        'Kc::ApiHealthCheck',
      description: 'Health endpoint URL for the Discord bot.',
      options:     {},
      state:       'http://zammad-discord-bot:3100/healthz',
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    Setting.create_if_not_exists(
      title:       'KC Discord Bot Health Check — Interval',
      name:        'kc_discord_bot_health_check_interval',
      area:        'Kc::ApiHealthCheck',
      description: 'How often (in seconds) to poll the health endpoint.',
      options:     {},
      state:       30,
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    Setting.create_if_not_exists(
      title:       'KC Discord Bot Health Check — Failure Threshold',
      name:        'kc_discord_bot_health_check_failure_threshold',
      area:        'Kc::ApiHealthCheck',
      description: 'Number of consecutive failures before creating an alert ticket.',
      options:     {},
      state:       4,
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    Setting.create_if_not_exists(
      title:       'KC Discord Bot Health Check — Alert Priority',
      name:        'kc_discord_bot_health_check_priority_id',
      area:        'Kc::ApiHealthCheck',
      description: 'Priority for Discord bot alert tickets. nil defaults to highest available.',
      options:     {},
      state:       nil,
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    Setting.create_if_not_exists(
      title:       'KC Discord Bot Health Check — Alert Group',
      name:        'kc_discord_bot_health_check_group_id',
      area:        'Kc::ApiHealthCheck',
      description: 'Group for Discord bot alert tickets. nil falls back to API health check group.',
      options:     {},
      state:       nil,
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    Setting.create_if_not_exists(
      title:       'KC Discord Bot Health Check — Alert Owner',
      name:        'kc_discord_bot_health_check_owner_id',
      area:        'Kc::ApiHealthCheck',
      description: 'Owner for Discord bot alert tickets. nil = unassigned.',
      options:     {},
      state:       nil,
      preferences: { permission: ['admin'] },
      frontend:    true,
    )

    Scheduler.create_if_not_exists(
      name:          'Check KC Discord Bot health.',
      method:        'Kc::DiscordBotHealthCheckJob.perform_now',
      period:        30.seconds,
      prio:          4,
      active:        true,
      updated_by_id: 1,
      created_by_id: 1,
      last_run:      Time.current,
    )
  end

  def down
    Scheduler.find_by(name: 'Check KC Discord Bot health.')&.destroy
    Setting.where("name LIKE 'kc_discord_bot_health_check_%'").destroy_all
  end
end
