# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Integration::GitLabController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  SENSITIVE_FIELDS = [:api_token].freeze

  def verify
    unmasked_params = unmask_sensitive_params(params, Setting.get('gitlab_config'))

    gitlab = ::GitLab.new(endpoint: unmasked_params[:endpoint], api_token: unmasked_params[:api_token], verify_ssl: unmasked_params[:verify_ssl])

    gitlab.verify!

    render json: {
      result: 'ok',
    }
  rescue => e
    logger.error e

    render json: {
      result:  'failed',
      message: e.message,
    }
  end

  def query
    issue_tracker_list_service = if params[:ticket_id]
                                   Service::Ticket::ExternalReferences::IssueTracker::TicketList.new(
                                     type:   'gitlab',
                                     ticket: Ticket.find(params[:ticket_id]),
                                   )
                                 else
                                   Service::Ticket::ExternalReferences::IssueTracker::FetchMetadata.new(
                                     type:        'gitlab',
                                     issue_links: params[:links],
                                   )
                                 end

    render json: {
      result:   'ok',
      response: issue_tracker_list_service.execute,
    }
  rescue => e
    logger.error e

    render json: {
      result:  'failed',
      message: e.message,
    }
  end

  def update
    ticket = Ticket.find(params[:ticket_id])
    ticket.with_lock do
      authorize!(ticket, :show?)
      ticket.preferences[:gitlab] ||= {}
      ticket.preferences[:gitlab][:issue_links] = Array(params[:issue_links]).uniq
      ticket.save!
    end

    render json: {
      result: 'ok',
    }
  end
end
