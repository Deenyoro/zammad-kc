# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class AI::Service::TextTool < AI::Service
  def self.persistent_lookup_attributes(context_data, _locale)
    {
      identifier:   'text_tool',
      triggered_by: context_data[:text_tool],
    }
  end

  def self.persistent_version(context_data, _locale)
    "#{context_data[:text_tool].id}-#{context_data[:text_tool].cache_version}"
  end

  def analytics?
    true
  end

  private

  def options
    {
      temperature: 0.1,
    }
  end

  def json_response?
    false
  end
end
