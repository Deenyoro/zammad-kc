# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

module Service::AI::VectorDB
  class Rebuild < Service::AI::VectorDB::Base
    attr_reader :worker

    def initialize(worker: 0)
      super()

      @worker = worker
    end

    def execute
      Service::AI::VectorDB::DropTable.new.execute
      Service::AI::VectorDB::CreateTable.new.execute
      Service::AI::VectorDB::Reload.new(worker:).execute
    end
  end
end
