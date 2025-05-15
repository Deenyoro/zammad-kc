# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class Service::AIAssistance::TextTools < Service::BaseWithCurrentUser
  attr_reader :input, :service_type

  def initialize(input:, service_type:, current_user: nil)
    super(current_user:) if current_user.present?

    @input = input
    @service_type = service_type
  end

  def execute
    return if input.blank?

    Service::CheckFeatureEnabled.new(name: 'ai_assistance_text_tools').execute
    Service::CheckFeatureEnabled.new(name: 'ai_provider', custom_error_message: __('AI provider is not configured.')).execute

    text_tool = ai_text_tool_service_class.new(
      current_user:,
      context_data: {
        input:
      }
    )

    text_tool.execute
  end

  private

  def ai_text_tool_service_class
    "AI::Service::Text#{service_type.classify}".constantize
  rescue
    raise ArgumentError, __("AI assistance text tool service type '#{service_type}' is not supported.")
  end
end
