# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class AI::Provider
  include Mixin::RequiredSubPaths
  include AI::Provider::Concerns::HandlesResponse

  DEFAULT_OPTIONS = {}.freeze

  EMBEDDING_SIZES = {}.freeze

  attr_accessor :config, :options

  def initialize(config: {}, options: {})
    @config  = config.presence || Setting.get('ai_provider_config')
    @options = self.class::DEFAULT_OPTIONS.merge(options.deep_symbolize_keys)
  end

  class << self
    def list
      @list ||= descendants.sort_by(&:name)
    end

    def by_name(name)
      "AI::Provider::#{name.classify}".safe_constantize
    end

    def ping!(_config)
      raise 'not implemented'
    end
  end

  def ask(prompt_system:, prompt_user:)
    result = chat(prompt_system:, prompt_user:)

    return result if !options[:json_response]

    begin
      JSON.parse(result)
    rescue => e
      Rails.logger.error "Unable to parse JSON response: #{e.inspect}"
      Rails.logger.error "Response: #{result}"

      raise ResponseError, __('Unable to process response')
    end
  end

  def embed(input:)
    embeddings(input:)
  end

  def metadata
    {
      provider:    self.class.name,
      temperature: options[:temperature],
    }.merge(specific_metadata)
  end

  private

  def specific_metadata
    {}
  end

  def chat(prompt_system:, prompt_user:)
    raise 'not implemented'
  end

  def embeddings(input:)
    raise 'not implemented'
  end

  class RequestError < StandardError; end
  class ResponseError < StandardError; end
end
