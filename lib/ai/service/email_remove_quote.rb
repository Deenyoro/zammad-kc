# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class AI::Service::EmailRemoveQuote < AI::Service
  private

  def options
    {
      temperature: 0,
    }
  end

  def cachable?
    true
  end

  def cache_key
    @cache_key ||= "ai::service::article-email-remove-quoted::#{context_data[:article].id}"
  end
end
