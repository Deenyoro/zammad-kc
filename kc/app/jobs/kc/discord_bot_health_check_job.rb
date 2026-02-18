# frozen_string_literal: true

# KC: Background job for Discord bot health monitoring.
#
# Called by Scheduler every 30 seconds. Delegates to
# Kc::DiscordBotHealthCheckService which polls the bot's /healthz
# endpoint and creates alert tickets after consecutive failures.
#
# Safety:
#   - safe_constantize on service class
class Kc::DiscordBotHealthCheckJob < ApplicationJob

  def perform
    service_class = 'Kc::DiscordBotHealthCheckService'.safe_constantize
    if service_class.nil?
      Rails.logger.warn 'KC: DiscordBotHealthCheckJob — DiscordBotHealthCheckService class not found'
      return
    end

    service_class.new.execute
  end
end
