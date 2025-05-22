# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class AI::Service::TicketSummarize < AI::Service
  def self.persistent_lookup_attributes(context_data, locale)
    {
      identifier:     'ticket_summarize',
      locale:,
      related_object: context_data[:ticket],
    }
  end

  def self.persistent_version(context_data, _locale)
    context_data[:ticket]
      .articles
      .summarizable
      .cache_version(:created_at)
  end

  def persistable?
    true
  end

  private

  def options
    {
      temperature: 0.1,
    }
  end
end
