# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class AI::Service::TicketSummarize < AI::Service
  def self.cache_key(ticket, locale)
    "ai::service::ticket_summarize::#{ticket.id}::#{ticket.articles.summarizable.cache_version(:created_at)}::#{locale}"
  end

  private

  def options
    {
      temperature: 0.1,
    }
  end

  def cachable?
    true
  end

  def cache_key
    @cache_key ||= self.class.cache_key(context_data[:ticket], locale)
  end
end
