# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# KC: Gives group conversations opened before 0.0.17 their group name.
#
#   Teams group/meeting chats: "Teams group chat: <topic>" or the members'
#     names, instead of "Teams Message from Group Chat #hread.v2" or the
#     first sender's name. Chat details come from the ticket's stored
#     audience, else from Graph (GET /chats/{id}?$expand=members).
#   RingCentral group texts: "Group SMS: <members>" instead of
#     "SMS from <first sender>".
#
# Only titles the integration generated are changed (Kc::TeamsChatTitle
# .replaceable?, or the SMS title template); a title an agent typed stays.
# Idempotent. Triggers and notifications are off for every write.
#
#   Kc::BackfillGroupChatTitlesJob.new.perform(dry_run: true)
#   Kc::BackfillGroupChatTitlesJob.new.perform
#   Kc::BackfillGroupChatTitlesJob.new.perform(include_closed: true)
class Kc::BackfillGroupChatTitlesJob < ApplicationJob
  DISPATCH_DISABLE = ['Transaction::Trigger', 'Transaction::Notification'].freeze

  def perform(dry_run: false, include_closed: false, teams: true, sms: true)
    report = Hash.new(0)
    report[:tickets] = []
    @graph_clients = {}

    each_ticket('teams_chat', include_closed) { |t| backfill_teams(t, dry_run, report) } if teams
    each_ticket('ringcentral_sms', include_closed) { |t| backfill_sms(t, dry_run, report) } if sms
    report
  end

  private

  def closed_state_ids
    @closed_state_ids ||= Ticket::State.joins(:state_type)
                                       .where(ticket_state_types: { name: %w[closed merged removed] })
                                       .pluck(:id)
  end

  def each_ticket(prefs_key, include_closed)
    scope = Ticket.where('preferences LIKE ?', "%#{prefs_key}:%").reorder(:id)
    scope = scope.where.not(state_id: closed_state_ids) unless include_closed
    scope.find_each do |ticket|
      yield ticket
    rescue => e
      Rails.logger.error "KC Group Chat Titles: ticket #{ticket.id} failed: #{e.message}"
    end
  end

  def backfill_teams(ticket, dry_run, report)
    chat = ticket.preferences.to_h.with_indifferent_access[:teams_chat].to_h.with_indifferent_access
    return if chat[:chat_id].blank?

    template = Setting.get('kc_teams_chat_ticket_title_template').to_s.presence
    return report[:teams_kept] += 1 unless Kc::TeamsChatTitle.replaceable?(ticket.title, auto_title: chat[:auto_title], template: template)

    # Closed tickets from before the audience was stored are looked up in
    # Graph only when their title is the legacy group title: there are
    # hundreds of closed 1:1 chats.
    open_ticket = !closed_state_ids.include?(ticket.state_id)
    graph_ok    = open_ticket || ticket.title.to_s.match?(Kc::TeamsChatTitle::LEGACY_GROUP_TITLE)
    info = chat_details(chat, graph_ok: graph_ok)
    if info.nil?
      report[:teams_unknown] += 1
      return
    end
    return report[:teams_one_on_one] += 1 unless Kc::TeamsChatTitle.group?(info[:chat_type])

    name = Kc::TeamsChatTitle.chat_name(**info)
    return report[:teams_unknown] += 1 if name.blank?

    title = Kc::TeamsChatTitle.group_title(name, template: Setting.get('kc_teams_chat_group_ticket_title_template'))
    write(ticket, title, dry_run, report, :teams) do |prefs|
      teams = (prefs.delete(:teams_chat) || prefs.delete('teams_chat') || {}).to_h.deep_symbolize_keys
      prefs[:teams_chat] = teams.merge(auto_title: title)
    end
  end

  # chat_type/topic/members for Kc::TeamsChatTitle.chat_name, or nil.
  def chat_details(chat, graph_ok: true)
    audience = chat[:audience].to_h.with_indifferent_access
    if audience[:chat_type].present? && audience[:topic].present?
      return { chat_type: audience[:chat_type], topic: audience[:topic], members: [] }
    end

    graph = graph_ok ? graph_for(chat[:tenant_id]) : nil
    if graph
      begin
        info = graph.get_chat(chat[:chat_id]).to_h.with_indifferent_access
        account = @graph_clients[:"account_#{chat[:tenant_id]}"]
        return { chat_type: info[:chatType], topic: info[:topic], members: Array(info[:members]), account_user_id: account }
      rescue => e
        Rails.logger.warn "KC Group Chat Titles: Graph chat lookup failed: #{e.message}"
      end
    end

    return nil if audience[:chat_type].blank?

    { chat_type: audience[:chat_type], topic: audience[:topic], members: Array(audience[:members]) }
  end

  def graph_for(tenant_id)
    key = tenant_id.to_s
    return @graph_clients[key] if @graph_clients.key?(key)

    graph_class = 'Kc::MicrosoftTeamsGraph'.safe_constantize
    channel = Channel.where(area: 'MicrosoftTeamsChat::Account', active: true).detect do |c|
      key.blank? || c.options.with_indifferent_access[:tenant_id].to_s.casecmp?(key)
    end
    @graph_clients[:"account_#{key}"] = channel&.options&.with_indifferent_access&.dig(:user_id)
    @graph_clients[key] = channel && graph_class ? graph_class.with_channel_tokens(channel) : nil
  rescue => e
    Rails.logger.warn "KC Group Chat Titles: no Graph client for tenant #{key}: #{e.message}"
    @graph_clients[key] = nil
  end

  def backfill_sms(ticket, dry_run, report)
    sms = ticket.preferences.to_h.with_indifferent_access[:ringcentral_sms].to_h.with_indifferent_access
    others = Array(sms[:participants]).compact_blank.select { |n| Kc::RingcentralApi.textable_number?(n) }
    return if others.size < 2

    template = Setting.get('kc_ringcentral_sms_ticket_title_template').to_s.presence || 'SMS from {phone}'
    prefix   = template.split('{phone}').first.to_s
    current  = ticket.title.to_s
    group_prefix = (Setting.get('kc_ringcentral_sms_group_ticket_title_template').to_s.presence ||
                    Channel::Driver::KcRingcentralSms::GROUP_TITLE_TEMPLATE).split('{participants}').first.to_s
    return report[:sms_kept] += 1 if current.start_with?(group_prefix) || prefix.blank? || !current.start_with?(prefix)

    contacts = 'Kc::PhoneContacts'.safe_constantize
    names = others.map { |n| contacts&.name_for(n).presence || n }
    title = Channel::Driver::KcRingcentralSms.group_ticket_title(names)
    write(ticket, title, dry_run, report, :sms) do |prefs|
      rc = (prefs.delete(:ringcentral_sms) || prefs.delete('ringcentral_sms') || {}).to_h.deep_symbolize_keys
      prefs[:ringcentral_sms] = rc.merge(group: true)
    end
  end

  def write(ticket, title, dry_run, report, kind)
    return report[:"#{kind}_unchanged"] += 1 if ticket.title == title

    report[:tickets] << { id: ticket.id, number: ticket.number, kind: kind, from: ticket.title, to: title }
    return report[:"#{kind}_would_update"] += 1 if dry_run

    Transaction.execute(disable: DISPATCH_DISABLE, reset_user_id: true) do
      prefs = (ticket.preferences || {}).deep_dup
      yield prefs
      ticket.update!(title: title, preferences: prefs, updated_by_id: 1)
    end
    report[:"#{kind}_updated"] += 1
  end
end
