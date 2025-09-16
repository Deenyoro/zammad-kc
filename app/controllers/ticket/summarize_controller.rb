# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class Ticket::SummarizeController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  def summarize
    Service::CheckFeatureEnabled.new(name: 'ai_assistance_ticket_summary', custom_exception_class: Exceptions::UnprocessableEntity).execute
    Service::CheckFeatureEnabled.new(name: 'ai_provider', custom_error_message: __('AI provider is not configured.')).execute

    ticket = Ticket.find(params[:id])
    authorize!(ticket, :agent_read_access?)

    summarize_service = Service::Ticket::AIAssistance::Summarize.new(
      locale:               current_user.locale,
      ticket:,
      persistence_strategy: :stored_only,
    )

    if (stored_content = summarize_service.execute&.content)
      # Fetch last article for the ticket to determine the relevance of the summary.
      last_article = ::Ticket::Article.last_customer_agent_article(ticket.id)

      render json: {
        result: {
          **stored_content,
          fingerprint_md5:           Digest::MD5.hexdigest(stored_content.sort.to_h.to_s),
          relevant_for_current_user: last_article&.author&.id != current_user.id,
        },
      }
      return
    end

    # Trigger background job to generate summary...
    TicketAIAssistanceSummarizeJob.perform_later(ticket, current_user.locale)

    render json: { result: nil }
  end
end
