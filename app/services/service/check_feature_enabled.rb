# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class Service::CheckFeatureEnabled < Service::Base
  include Service::Concerns::HandlesSetting

  attr_reader :name, :exception, :custom_error_message

  def initialize(name: nil, exception: true, custom_error_message: nil)
    super()
    @name = name
    @exception = exception
    @custom_error_message = custom_error_message
  end

  def execute
    enabled = setting_enabled?(@name)
    return enabled if !@exception

    raise FeatureDisabledError, @custom_error_message if !enabled
  end

  class FeatureDisabledError < StandardError
    def initialize(message = nil)
      super(message || __('This feature is not enabled.'))
    end
  end
end
