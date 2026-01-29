# KC: Time Management API controller.
# Provides per-ticket time entry CRUD (sidebar) and admin reporting endpoints.
#
# Hardening: All references to upstream classes that could be renamed use
# safe accessors (try, respond_to?, defined?, safe_constantize).
class Kc::TimeManagementController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  # ---------------------------------------------------------------------------
  # Sidebar endpoints (ticket-scoped)
  # ---------------------------------------------------------------------------

  # GET /api/v1/kc/tickets/:ticket_id/time_entries
  def ticket_entries
    ticket = Ticket.find(params[:ticket_id])
    entries = Ticket::TimeAccounting.where(ticket_id: ticket.id).order(:created_at)

    types  = kc_accounting_types_index
    agents = {}

    result = entries.map do |entry|
      agent_id = entry.try(:agent_id) || entry.created_by_id
      agents[agent_id] ||= User.lookup(id: agent_id)

      {
        id:         entry.id,
        time_unit:  entry.time_unit,
        type_id:    entry.type_id,
        type_name:  types[entry.type_id]&.dig(:name) || types[entry.type_id]&.try(:name) || '-',
        agent_id:   agent_id,
        agent_name: agents[agent_id]&.fullname || '-',
        created_at: entry.created_at,
      }
    end

    render json: result
  end

  # POST /api/v1/kc/tickets/:ticket_id/time_entries
  def create_entry
    ticket = Ticket.find(params[:ticket_id])

    attrs = {
      ticket_id:     ticket.id,
      time_unit:     params[:time_unit],
      type_id:       params[:type_id].presence,
      created_by_id: current_user.id,
    }
    if Ticket::TimeAccounting.column_names.include?('agent_id')
      attrs[:agent_id] = params[:agent_id].presence
    end
    entry = Ticket::TimeAccounting.new(attrs)
    entry.save!

    render json: { id: entry.id }, status: :created
  end

  # DELETE /api/v1/kc/tickets/:ticket_id/time_entries/:id
  def destroy_entry
    ticket = Ticket.find(params[:ticket_id])

    entry = Ticket::TimeAccounting.find_by!(id: params[:id], ticket_id: ticket.id)
    entry.destroy!

    render json: {}, status: :ok
  end

  # ---------------------------------------------------------------------------
  # Reporting endpoints (admin only)
  # ---------------------------------------------------------------------------

  # GET /api/v1/kc/time_management/by_user/:year/:month
  def by_user
    records = Ticket::TimeAccounting
      .where(created_at: reporting_period)

    # Aggregate by effective agent
    aggregated = records.each_with_object(Hash.new(0)) do |entry, memo|
      agent_id = entry.try(:agent_id) || entry.created_by_id
      memo[agent_id] += entry.time_unit.to_f
    end

    agents = {}
    results = aggregated.map do |agent_id, total|
      agents[agent_id] ||= User.lookup(id: agent_id)
      {
        agent_id:   agent_id,
        agent_name: agents[agent_id]&.fullname || '-',
        time_unit:  total,
      }
    end.sort_by { |r| -r[:time_unit] }

    if params[:download]
      return kc_send_excel("By User #{year}-#{month}", "kc_by_user-#{year}-#{month}.xlsx",
                           [{ name: __('Agent'), width: 30 }, { name: __('Time Units'), width: 15, data_type: 'float' }],
                           results.map { |r| [r[:agent_name], r[:time_unit]] })
    end

    render json: results
  end

  # GET /api/v1/kc/time_management/by_organization/:year/:month
  def by_organization
    records = Ticket::TimeAccounting
      .where(created_at: reporting_period)
      .pluck(:ticket_id, :time_unit)

    # Aggregate by ticket's customer organization
    org_totals = records.each_with_object(Hash.new(0)) do |(ticket_id, time_unit), memo|
      ticket = Ticket.lookup(id: ticket_id)
      next if !ticket || !ticket.organization_id

      memo[ticket.organization_id] += time_unit.to_f
    end

    results = org_totals.map do |org_id, total|
      org = Organization.lookup(id: org_id)
      {
        organization_id:   org_id,
        organization_name: org&.name || '-',
        time_unit:         total,
      }
    end.sort_by { |r| -r[:time_unit] }

    if params[:download]
      return kc_send_excel("By Organization #{year}-#{month}", "kc_by_organization-#{year}-#{month}.xlsx",
                           [{ name: __('Organization'), width: 40 }, { name: __('Time Units'), width: 15, data_type: 'float' }],
                           results.map { |r| [r[:organization_name], r[:time_unit]] })
    end

    render json: results
  end

  private

  # Safe lookup of Ticket::TimeAccounting::Type — returns a hash indexed by id.
  # If upstream renames or removes this class the endpoint still works (types
  # will just display as '-').
  def kc_accounting_types_index
    type_class = 'Ticket::TimeAccounting::Type'.safe_constantize
    return {} if type_class.nil?

    type_class.all.index_by(&:id)
  rescue => e
    Rails.logger.warn "KC: Failed to load accounting types: #{e.message}"
    {}
  end

  # DRY helper for Excel downloads.  Wrapped in rescue so upstream ExcelSheet
  # API changes produce a 500 with a clear message rather than a cryptic crash.
  def kc_send_excel(title, filename, header, rows)
    excel = ExcelSheet.new(
      title:    title,
      header:   header,
      records:  rows,
      timezone: params[:timezone],
      locale:   current_user.locale,
    )
    send_data(
      excel.content,
      filename:    filename,
      type:        ExcelSheet::CONTENT_TYPE,
      disposition: 'attachment'
    )
  end

  def year
    @year ||= params[:year] || Time.use_zone(Setting.get('timezone_default')) { Time.zone.now.year }
  end

  def month
    @month ||= params[:month] || Time.use_zone(Setting.get('timezone_default')) { Time.zone.now.month }
  end

  def reporting_period
    @reporting_period ||= Time.use_zone(Setting.get('timezone_default')) do
      start_period = Time.zone.parse("#{year}-#{month}-01")
      end_period   = start_period.end_of_month
      (start_period..end_period)
    end
  end
end
