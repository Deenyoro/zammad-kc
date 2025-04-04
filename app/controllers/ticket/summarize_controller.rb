# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class Ticket::SummarizeController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  def enqueue
    Service::CheckFeatureEnabled.new(name: 'ai_assistance_ticket_summary').execute
    Service::CheckFeatureEnabled.new(name: 'ai_provider', custom_error_message: __('AI provider is not configured.')).execute

    ticket = Ticket.find(params[:id])
    authorize!(ticket, :agent_read_access?)

    cache_key = AI::Service::TicketSummarize.cache_key(ticket, current_user.locale)
    cache     = Rails.cache.read(cache_key)

    if cache.present?
      render json: {
        result: {
          problem:              cache['problem'],
          conversation_summary: cache['summary'],
          open_questions:       cache['open_questions'],
          suggestions:          cache['suggestions'],
        },
      }
      return
    end

    # Trigger background job to generate summary...
    TicketAIAssistanceSummarizeJob.perform_later(ticket, current_user.locale)

    render json: { result: nil }
  end
end
