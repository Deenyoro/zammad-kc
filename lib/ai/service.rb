# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class AI::Service
  include Mixin::RequiredSubPaths

  PROMPT_PATH_STRING = Rails.root.join('lib/ai/service/prompts/%{type}/%{service}.txt.erb').to_s.freeze

  attr_reader :current_user, :context_data, :locale, :persistence_strategy, :additional_options

  Result = Struct.new(:content, :stored_result, :fresh, keyword_init: true)

  def self.list
    @list ||= descendants.sort_by(&:name)
  end

  # @param persistence_strategy [Symbol, NilClass] :stored_or_request, :stored_only, :request_only.
  def initialize(context_data:, current_user: nil, persistence_strategy: :stored_or_request, prompt_system: nil, prompt_user: nil, locale: nil, additional_options: {})
    @context_data         = context_data
    @current_user         = current_user
    @prompt_system        = prompt_system
    @prompt_user          = prompt_user
    @persistence_strategy = persistence_strategy
    @additional_options   = additional_options
    @locale               = Locale.find_by(locale: locale || @current_user&.locale || Locale.default)
  end

  def self.name_service
    name.sub('AI::Service::', '')
  end

  # @return [Result] result of the AI service
  def execute
    case persistence_strategy
    when :stored_or_request
      fetch_stored || request_fresh
    when :stored_only
      fetch_stored
    when :request_only
      request_fresh
    end
  end

  def self.persistent_lookup_attributes(_context_data, _locale)
    raise 'not implemented'
  end

  def self.persistent_version(_context_data, _locale)
    raise 'not implemented'
  end

  private

  def fetch_stored
    return if !persistable?

    stored_result = AI::StoredResult.find_by(persistent_lookup_attributes_with_version)

    return if !stored_result

    Result.new(content: stored_result.content, stored_result:, fresh: false)
  end

  def request_fresh
    response = ask_provider

    return if response.blank?

    stored_result = save_result(response) if persistable?

    Result.new(content: response, stored_result:, fresh: true)
  end

  def ask_provider
    current_prompt_system = @prompt_system || render_prompt(prompt_system)
    current_prompt_user   = @prompt_user   || render_prompt(prompt_user)

    Rails.logger.error "current_prompt_system: #{current_prompt_system}"
    Rails.logger.error "current_prompt_user: #{current_prompt_user}"

    provider.ask(prompt_system: current_prompt_system, prompt_user: current_prompt_user)
  end

  def provider
    @provider ||= AI::Provider.by_name(provider_name).new(
      options: options.merge({ service_name: self.class.name_service, json_response: json_response? })
    )
  end

  def provider_name
    @provider_name ||= Setting.get('ai_provider')
  end

  def save_result(result)
    AI::StoredResult.upsert!(result, persistent_lookup_attributes, persistent_version, provider.metadata)
  end

  def persistable?
    false
  end

  def persistent_lookup_attributes_with_version
    persistent_lookup_attributes.merge(version: persistent_version)
  end

  def persistent_lookup_attributes
    self.class.persistent_lookup_attributes(context_data, locale)
  end

  def persistent_version
    self.class.persistent_version(context_data, locale)
  end

  def json_response?
    true
  end

  def options
    {}
  end

  def prompt_file_name
    @prompt_file_name ||= self.class.name_service.underscore
  end

  def prompt_system
    File.read(format(PROMPT_PATH_STRING, type: 'system', service: prompt_file_name))
  end

  def prompt_user
    File.read(format(PROMPT_PATH_STRING, type: 'user', service: prompt_file_name))
  end

  def render_prompt(prompt_template)
    ERB.new(prompt_template.to_s, trim_mode: '-').result(binding)
  end
end
