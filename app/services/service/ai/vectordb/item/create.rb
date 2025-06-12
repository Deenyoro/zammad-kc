# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

module Service::AI::VectorDB::Item
  class Create < Service::AI::VectorDB::Base
    attr_reader :object_id, :object_name, :content, :metadata

    def initialize(object_id:, object_name:, content:, metadata: {})
      super()

      @object_id = object_id
      @object_name = object_name
      @content = content
      @metadata = metadata
    end

    def execute
      embedding = AI::Provider.by_name(Setting.get('ai_provider')).new.embed(input: content)

      ai_vector_db.create(object_id:, object_name:, content:, metadata:, embedding:)
    end
  end
end
