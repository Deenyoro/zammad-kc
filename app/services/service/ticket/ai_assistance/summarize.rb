# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class Service::Ticket::AIAssistance::Summarize < Service::BaseWithCurrentUser
  attr_reader :ticket, :locale

  def initialize(ticket:, current_user: nil, locale: nil)
    super(current_user:) if current_user.present?

    @ticket = ticket
    @locale = locale
  end

  def execute
    Service::CheckFeatureEnabled.new(name: 'ai_assistance_ticket_summary').execute
    Service::CheckFeatureEnabled.new(name: 'ai_provider', custom_error_message: __('AI provider is not configured.')).execute

    return if ticket.articles.none?

    summarize = AI::Service::TicketSummarize.new(
      current_user:,
      locale:,
      context_data: {
        ticket:,
        config: Setting.get('ai_assistance_ticket_summary_config')
      }
    )

    summarize.execute
  end
end
