# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class AI::Provider
  include Mixin::RequiredSubPaths
  include AI::Provider::Concerns::HandlesResponse

  attr_reader :prompt_system, :prompt_user, :config, :options

  def initialize(prompt_system:, prompt_user:, config: {}, options: {})
    @prompt_system = prompt_system
    @prompt_user   = prompt_user
    @config        = config.presence || Setting.get('ai_provider_config')
    @options       = options.deep_symbolize_keys
  end

  class << self
    def list
      @list ||= descendants.sort_by(&:name)
    end

    def by_name(name)
      "AI::Provider::#{name.classify}".safe_constantize
    end

    def accessible!
      raise 'Not implemented' # rubocop:disable Zammad/DetectTranslatableString
    end

  end

  def process
    result = request

    begin
      return JSON.parse(result)
    rescue => e
      Rails.logger.error "Unable to parse JSON response: #{e.inspect}"
      Rails.logger.error "Response: #{result}"

      raise ResponseError, __('Unable to process response')
    end

    result
  end

  private

  def request
    raise 'Not implemented' # rubocop:disable Zammad/DetectTranslatableString
  end

  class RequestError < StandardError; end
  class ResponseError < StandardError; end
end
