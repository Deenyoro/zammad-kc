# KC: Background job for proactive API connection health checks.
#
# Called by Scheduler every 5 minutes. Delegates to Kc::ApiHealthCheckService
# which checks all monitored channels and creates alert tickets on failure.
#
# Safety:
#   - safe_constantize on service class
#   - Each channel checked independently (errors don't block others)
class Kc::ApiHealthCheckJob < ApplicationJob

  def perform
    service_class = 'Kc::ApiHealthCheckService'.safe_constantize
    if service_class.nil?
      Rails.logger.warn 'KC: ApiHealthCheckJob — ApiHealthCheckService class not found'
      return
    end

    service_class.new.execute
  end

  def self.perform_now
    new.perform
  end
end
