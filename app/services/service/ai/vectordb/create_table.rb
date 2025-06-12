# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

module Service::AI::VectorDB
  class CreateTable < Service::AI::VectorDB::Base
    def execute
      ai_vector_db.ping!(only_version: true)

      provider = AI::Provider.by_name(Setting.get('ai_provider'))

      embedding_sizes = provider.const_get(:EMBEDDING_SIZES)
      embedding_size = embedding_sizes.fetch(provider.const_get(:DEFAULT_OPTIONS)[:embedding_model])

      ai_vector_db.migrate(dimensions: embedding_size)
    end
  end
end
