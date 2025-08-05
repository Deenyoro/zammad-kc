# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

module Zammad
  module Service
    class Redis < ::Redis
      MIN_VERSION = '6'.freeze

      def initialize
        url = ENV['REDIS_URL'].presence || 'redis://localhost:6379'
        driver = url.start_with?('rediss://') ? :ruby : :hiredis

        super(url: url, driver: driver).tap do
          ensure_version!
        end
      end

      private

      def ensure_version!
        current_version = info['redis_version']

        return if Gem::Version.new(current_version) >= Gem::Version.new(MIN_VERSION)

        warn "Error: incompatible Redis version (#{MIN_VERSION}+ required; #{current_version} found)."
        exit 1 # rubocop:disable Rails/Exit
      end
    end
  end
end
