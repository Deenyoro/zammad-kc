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
#   - Attachments are copied from the form's UploadCache into storage owned
#     by the scheduled reply at schedule time; "Edit" (DELETE with
#     restore_form_id) copies them back into the compose form
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
      render json: { error: __('Scheduled articles not available') }, status: :unprocessable_content
      return
    end

    article_data = params[:article_data]
    if article_data.blank?
      render json: { error: __('Article data is required') }, status: :unprocessable_content
      return
    end

    # Fail-fast: validate body is present at creation time (not just at execution)
    article_hash = article_data_hash(article_data)
    body = article_hash[:body] || article_hash['body']
    if body.blank?
      render json: { error: __('Article body is required') }, status: :unprocessable_content
      return
    end

    scheduled_at = begin
      Time.zone.parse(params[:scheduled_at].to_s)
    rescue ArgumentError, TypeError
      nil
    end
    if scheduled_at.nil? || scheduled_at <= Time.current
      render json: { error: __('Scheduled time must be in the future') }, status: :unprocessable_content
      return
    end
    if scheduled_at > Time.current + MAX_SCHEDULE_WINDOW
      render json: { error: __('Scheduled time cannot be more than 90 days in the future') }, status: :unprocessable_content
      return
    end

    # Rate limit: max pending per ticket
    existing_count = kc_model_class.pending.where(ticket_id: ticket.id).count
    if existing_count >= MAX_PENDING_PER_TICKET
      render json: { error: __('Too many pending scheduled replies for this ticket (max %s)').gsub('%s', MAX_PENDING_PER_TICKET.to_s) }, status: :unprocessable_content
      return
    end

    ticket_attrs = ticket_attrs_hash(params[:ticket_attributes])

    # The form's files are copied into storage owned by the scheduled reply,
    # so form_id itself is not kept (see Kc::ScheduledArticle).
    form_id = article_hash.delete('form_id')

    scheduled = kc_model_class.new(
      ticket_id:         ticket.id,
      article_data:      article_hash,
      ticket_attributes: ticket_attrs,
      scheduled_at:      scheduled_at,
      status:            'pending',
      created_by_id:     current_user.id,
      updated_by_id:     current_user.id,
    )
    kc_model_class.transaction do
      scheduled.save!
      scheduled.store_attachments_from_form!(form_id, files: attachment_files_param, user_id: current_user.id)
    end

    render json: { id: scheduled.id, scheduled_at: scheduled.scheduled_at }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  # DELETE /api/v1/kc/tickets/:ticket_id/scheduled_articles/:id
  def destroy
    ticket = Ticket.find(params[:ticket_id])
    authorize!(ticket, :update?)

    if kc_model_class.nil?
      render json: { error: __('Scheduled articles not available') }, status: :unprocessable_content
      return
    end

    scheduled = kc_model_class.find_by(id: params[:id], ticket_id: ticket.id)
    if scheduled.nil?
      render json: { error: __('Scheduled reply not found') }, status: :not_found
      return
    end

    unless scheduled.status == 'pending'
      render json: { error: __('Only pending scheduled replies can be cancelled') }, status: :unprocessable_content
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

    # "Edit": put the reply's files back into the agent's compose form.
    restore_form_id = params[:restore_form_id].to_s.presence
    if restore_form_id && !restore_form_allowed?(restore_form_id)
      render json: { error: __('Invalid form') }, status: :unprocessable_content
      return
    end

    restored = cancel_and_restore!(scheduled, restore_form_id)

    render json: { status: 'cancelled', attachments: restored.map { |store| restored_attachment_json(store) } }, status: :ok
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

  def restore_form_allowed?(form_id)
    form_id.match?(%r{\A[\w-]{1,64}\z}) && UploadCachePolicy.new(current_user, UploadCache.new(form_id)).add?
  end

  # Cancels the reply; with a form id its files are first copied into that
  # form's upload cache. Returns the restored UploadCache items.
  def cancel_and_restore!(scheduled, restore_form_id)
    restored = []
    kc_model_class.transaction do
      restored = scheduled.restore_attachments_to_form!(restore_form_id, user_id: current_user.id) if restore_form_id
      scheduled.cancel!(
        cancelled_by_id:        current_user.id,
        keep_legacy_form_cache: restore_form_id.present? && restore_form_id == scheduled.article_data&.dig('form_id').to_s,
      )
    end
    restored
  end

  def restored_attachment_json(store)
    { id: store.id, filename: store.filename, size: store.size, contentType: store.preferences['Content-Type'] }
  end

  # Files selected in the new UI's compose form ([{ name:, type: }]). nil
  # when not sent (legacy UI): then every file of the form is taken.
  def attachment_files_param
    return nil if !params.key?(:attachments)

    Array(params[:attachments]).filter_map do |file|
      file = file.to_unsafe_h if file.respond_to?(:to_unsafe_h)
      next if !file.is_a?(Hash)

      { name: file['name'].to_s, type: file['type'].presence }
    end
  end

  def ticket_attrs_hash(param)
    return {} if param.blank?

    raw = param.respond_to?(:to_unsafe_h) ? param.to_unsafe_h : param.to_h
    raw.stringify_keys.slice(*PERMITTED_TICKET_KEYS)
  end
end
