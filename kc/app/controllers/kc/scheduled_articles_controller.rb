# KC: REST controller for scheduled article CRUD.
#
# Provides endpoints to list, create, and cancel scheduled articles
# for a given ticket. Only accessible to authenticated agents with
# ticket access.
#
# Safety:
#   - Agent permission required
#   - Ticket access authorization via Pundit
#   - Body validation at creation time (fail-fast)
#   - 90-day max scheduling window
#   - Rate limit: max 50 pending per ticket
#   - Owner check on cancel (or admin override)
class Kc::ScheduledArticlesController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  MAX_SCHEDULE_WINDOW = 90.days
  MAX_PENDING_PER_TICKET = 50

  # GET /api/v1/kc/tickets/:ticket_id/scheduled_articles
  def index
    ticket = Ticket.find(params[:ticket_id])
    authorize!(ticket, :show?)

    if kc_model_class.nil?
      render json: []
      return
    end

    scheduled = kc_model_class.pending.where(ticket_id: ticket.id).order(:scheduled_at)

    result = scheduled.map do |s|
      {
        id:                s.id,
        ticket_id:         s.ticket_id,
        article_data:      s.article_data,
        ticket_attributes: s.ticket_attributes,
        scheduled_at:      s.scheduled_at,
        status:            s.status,
        created_by_id:     s.created_by_id,
        created_at:        s.created_at,
      }
    end

    render json: result
  end

  # POST /api/v1/kc/tickets/:ticket_id/scheduled_articles
  def create
    ticket = Ticket.find(params[:ticket_id])
    authorize!(ticket, :update?)

    if kc_model_class.nil?
      render json: { error: __('Scheduled articles not available') }, status: :unprocessable_entity
      return
    end

    article_data = params[:article_data]
    if article_data.blank?
      render json: { error: __('Article data is required') }, status: :unprocessable_entity
      return
    end

    # Fail-fast: validate body is present at creation time (not just at execution)
    article_hash = article_data_hash(article_data)
    body = article_hash[:body] || article_hash['body']
    if body.blank?
      render json: { error: __('Article body is required') }, status: :unprocessable_entity
      return
    end

    scheduled_at = begin
      Time.zone.parse(params[:scheduled_at].to_s)
    rescue ArgumentError, TypeError
      nil
    end
    if scheduled_at.nil? || scheduled_at <= Time.current
      render json: { error: __('Scheduled time must be in the future') }, status: :unprocessable_entity
      return
    end
    if scheduled_at > Time.current + MAX_SCHEDULE_WINDOW
      render json: { error: __('Scheduled time cannot be more than 90 days in the future') }, status: :unprocessable_entity
      return
    end

    # Rate limit: max pending per ticket
    existing_count = kc_model_class.pending.where(ticket_id: ticket.id).count
    if existing_count >= MAX_PENDING_PER_TICKET
      render json: { error: __('Too many pending scheduled replies for this ticket (max %s)').gsub('%s', MAX_PENDING_PER_TICKET.to_s) }, status: :unprocessable_entity
      return
    end

    ticket_attrs = ticket_attrs_hash(params[:ticket_attributes])

    scheduled = kc_model_class.new(
      ticket_id:         ticket.id,
      article_data:      article_hash,
      ticket_attributes: ticket_attrs,
      scheduled_at:      scheduled_at,
      status:            'pending',
      created_by_id:     current_user.id,
      updated_by_id:     current_user.id,
    )
    scheduled.save!

    render json: { id: scheduled.id, scheduled_at: scheduled.scheduled_at }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # DELETE /api/v1/kc/tickets/:ticket_id/scheduled_articles/:id
  def destroy
    ticket = Ticket.find(params[:ticket_id])
    authorize!(ticket, :update?)

    if kc_model_class.nil?
      render json: { error: __('Scheduled articles not available') }, status: :unprocessable_entity
      return
    end

    scheduled = kc_model_class.find_by(id: params[:id], ticket_id: ticket.id)
    if scheduled.nil?
      render json: { error: __('Scheduled reply not found') }, status: :not_found
      return
    end

    unless scheduled.status == 'pending'
      render json: { error: __('Only pending scheduled replies can be cancelled') }, status: :unprocessable_entity
      return
    end

    # Only the creator (or an admin) can cancel a scheduled reply
    if scheduled.created_by_id != current_user.id && !current_user.permissions?('admin')
      raise Exceptions::Forbidden, __('You can only cancel your own scheduled replies')
    end

    # Log admin cancellations for audit trail
    if scheduled.created_by_id != current_user.id
      Rails.logger.info "KC: Admin #{current_user.id} (#{current_user.login}) cancelled scheduled article ##{scheduled.id} owned by user ##{scheduled.created_by_id}"
    end

    scheduled.cancel!(cancelled_by_id: current_user.id)

    render json: { status: 'cancelled' }, status: :ok
  end

  private

  def kc_model_class
    @kc_model_class ||= 'Kc::ScheduledArticle'.safe_constantize
  end

  PERMITTED_ARTICLE_KEYS = %w[
    body type type_id sender sender_id to cc bcc subject internal
    content_type form_id preferences subtype
  ].freeze

  PERMITTED_TICKET_KEYS = %w[
    state_id state priority_id priority owner_id owner
    group_id group pending_time
  ].freeze

  def article_data_hash(param)
    return {} if param.blank?

    raw = param.respond_to?(:to_unsafe_h) ? param.to_unsafe_h : param.to_h
    raw.stringify_keys.slice(*PERMITTED_ARTICLE_KEYS)
  end

  def ticket_attrs_hash(param)
    return {} if param.blank?

    raw = param.respond_to?(:to_unsafe_h) ? param.to_unsafe_h : param.to_h
    raw.stringify_keys.slice(*PERMITTED_TICKET_KEYS)
  end
end
