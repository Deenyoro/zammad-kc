# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class BackgroundServices
  class Service
    class ProcessDelayedAIJobs < BaseDelayedJobs

      # Use some parallelity by default for the slow AI
      def self.default_worker_threads
        5
      end

      def self.pre_launch
        start_time = Time.zone.now

        CleanupAction.cleanup_delayed_jobs(start_time, queues:)
      end

      def self.queues
        [:ai].freeze
      end
    end
  end
end
