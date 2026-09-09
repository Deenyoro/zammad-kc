# KC: Calls a human when a ticket escalation has gone unfixed.
#
# Zammad already tracks escalation_at per ticket via the SLA. This job
# reports every still-escalated ticket to the PBX connector on each run and
# lets the PBX decide when a call is actually due. That keeps the timing
# rules and the quiet-hours policy in one place, shared with the uptime
# alerts, instead of being reimplemented per alert source.
#
# The PBX applies the escalation policy: it waits until the ticket has been
# overdue for the configured delay, refuses to call overnight, and holds
# anything that came due during the night until the morning.
class Kc::EscalationCallJob < ApplicationJob

  def perform
    return if Setting.get('kc_escalation_call_enabled') != true

    channel = Channel.where(area: 'Freepbx::Account', active: true).order(:id).first
    if channel.nil?
      Rails.logger.warn 'KC Escalation Calls: no active FreePBX connection, cannot place calls'
      return
    end

    api_class = 'Kc::FreepbxApi'.safe_constantize
    return if api_class.nil?

    api      = api_class.for_channel(channel)
    reported = []

    escalated_tickets.each do |ticket|
      key = "zammad:escalation:#{ticket.id}"
      reported << key
      begin
        api.alert(
          key:     key,
          message: alert_message(ticket),
          since:   ticket.escalation_at.utc.iso8601,
          policy:  'escalation',
          source:  'zammad',
        )
      rescue StandardError => e
        Rails.logger.error "KC Escalation Calls: Failed to report ticket #{ticket.id}: #{e.message}"
      end
    end

    clear_resolved(api, reported)
  end

  # Class method called by Scheduler
  def self.perform_now
    new.perform
  end

  private

  # Tickets whose escalation has already passed and that nobody has closed.
  # States flagged ignore_escalation (the KC waiting/on-site/project states)
  # never carry an escalation_at, so they fall out naturally.
  def escalated_tickets
    open_state_ids = Ticket::State.by_category(:open).pluck(:id)
    return Ticket.none if open_state_ids.empty?

    Ticket
      .where(state_id: open_state_ids)
      .where.not(escalation_at: nil)
      .where(escalation_at: ...Time.current)
      .reorder(escalation_at: :asc)
      .limit(25)
  end

  def alert_message(ticket)
    overdue = ((Time.current - ticket.escalation_at) / 60).floor
    owner   = ticket.owner_id.to_i == 1 ? 'unassigned' : ticket.owner&.fullname.to_s
    parts = ["Ticket #{ticket.number} is #{overdue} minutes past its escalation time."]
    parts << "Subject: #{ticket.title}"
    parts << "Owner: #{owner}" if owner.present?
    parts.join(' ')
  end

  # Releases PBX bookkeeping for tickets that are no longer escalated, so a
  # future escalation on the same ticket is not swallowed by the cooldown.
  def clear_resolved(api, reported)
    tracked = Rails.cache.read(cache_key) || []
    (tracked - reported).each do |key|
      api.resolve_alert(key)
    rescue StandardError => e
      Rails.logger.warn "KC Escalation Calls: Failed to clear #{key}: #{e.message}"
    end
    Rails.cache.write(cache_key, reported, expires_in: 1.day)
  end

  def cache_key
    'kc_escalation_call:reported'
  end
end
