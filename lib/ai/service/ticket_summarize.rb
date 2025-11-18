# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class AI::Service::TicketSummarize < AI::Service
  def self.lookup_attributes(context_data, locale)
    {
      identifier:     'ticket_summarize',
      locale:,
      related_object: context_data[:ticket],
    }
  end

  def self.lookup_version(context_data, _locale)
    context_data[:ticket]
      .articles
      .without_system_notifications
      .cache_version(:created_at)
  end

  def persistable?
    true
  end

  def analytics?
    true
  end

  def validate_result!(result)
    raise InvalidResultKeysError if !result.key?('language')

    optional_keys = %w[
      customer_request
      conversation_summary
    ]

    raise InvalidResultKeysError if !optional_keys.intersect?(result.keys)
  end

  private

  def options
    {
      temperature: 0.1,
    }
  end

  class InvalidResultKeysError < StandardError
    def initialize
      super(__('AI service result is missing expected keys'))
    end
  end
end
