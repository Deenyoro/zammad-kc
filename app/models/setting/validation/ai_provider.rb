# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class Setting::Validation::AIProvider < Setting::Validation::Base

  PROVIDERS = AI::Provider.list.map { |provider| provider.name.demodulize.underscore }.freeze

  def run
    return result_success if value.blank?

    msg = validate_provider
    return result_failed(msg) if !msg.nil?

    result_success
  end

  private

  def validate_provider
    return __('AI provider is not supported') if PROVIDERS.exclude?(value)

    nil
  end
end
