# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

module Service::AI::VectorDB
  class Available < Service::AI::VectorDB::Base
    attr_reader :ping

    def initialize(ping: true)
      super()

      @ping = ping
    end

    def execute
      return false if !Service::CheckFeatureEnabled.new(name: 'ai_provider', exception: false).execute
      return true if !ping

      ai_vector_db.ping?
    end
  end
end
