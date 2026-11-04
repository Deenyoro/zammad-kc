# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Reuse a recently closed conversation only for an incoming customer message.
# Outbound capture must not reopen tickets.
class Kc::RecentConversationReopen
  WINDOW = 15.minutes
  LOCKED_STATES = ['closed (locked)', 'closed (locked until)'].freeze

  def self.call(preferences_key:, conversation_key:, message_time:, user_id:, channel_id: nil)
    return if conversation_key.blank?

    received_at = parse_message_time(message_time)
    closed_states = Ticket::State.joins(:state_type)
                                 .where(ticket_state_types: { name: 'closed' })
                                 .where.not(name: LOCKED_STATES)
    follow_up = Ticket::State.find_by(default_follow_up: true) || Ticket::State.find_by(name: 'open')
    return if follow_up.nil?

    # last_close_at changes on every close; close_at is only the FIRST close.
    scope = Ticket.where(state_id: closed_states.select(:id))
                  .where('COALESCE(last_close_at, close_at) BETWEEN ? AND ?', received_at - WINDOW, received_at)
                  .where('preferences LIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(conversation_key)}%")
                  .order(Arel.sql('COALESCE(last_close_at, close_at) DESC'), id: :desc)

    scope.each do |ticket|
      ticket.with_lock do
        prefs = (ticket.preferences || {}).with_indifferent_access[preferences_key]&.with_indifferent_access
        next unless prefs && prefs[:conversation_key].to_s == conversation_key
        next if channel_id && prefs[:channel_id].to_s != channel_id.to_s

        closed_at = ticket.last_close_at || ticket.close_at
        next unless closed_at && closed_at.between?(received_at - WINDOW, received_at)

        # Another incoming message may already have reopened this same ticket.
        return ticket if ticket.state_id == follow_up.id
        next unless closed_states.exists?(id: ticket.state_id)

        ticket.update!(state_id: follow_up.id, pending_time: nil, updated_by_id: user_id)
        return ticket if ticket.state_id == follow_up.id
      end
    end
    nil
  end

  def self.parse_message_time(value)
    (Time.zone.parse(value.to_s) if value.present?) || Time.current
  rescue ArgumentError, TypeError
    Time.current
  end
  private_class_method :parse_message_time
end
