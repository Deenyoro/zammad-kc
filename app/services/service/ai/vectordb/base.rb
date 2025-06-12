# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

module Service::AI::VectorDB
  class Base < Service::Base

    def ai_vector_db
      @ai_vector_db ||= ensure_ai_provider_configured! && AI::VectorDB.new
    end

    def ensure_ai_provider_configured!
      Service::CheckFeatureEnabled
        .new(name: 'ai_provider', custom_error_message: __('AI provider is not configured.'))
        .execute

      true
    end
  end
end
