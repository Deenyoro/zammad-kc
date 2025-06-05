# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class AIAssistanceController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  def text_tools
    output = Service::AIAssistance::TextTools.new(
      input:        params[:input],
      service_type: params[:service_type],
      current_user:,
    ).execute

    render json: {
      output: output[:content],
    }
  end
end
