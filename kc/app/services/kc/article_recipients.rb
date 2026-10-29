# KC: Who a Teams, SMS or call article went to, as one readable line for the
# article's `to` field.
#
# Email articles carry real To/Cc headers. The KC channels did not: an
# inbound text or Teams message had no `to` at all, and an agent's reply
# kept whatever the reply form put there (a bare number, or nothing for
# Teams), while the delivery jobs actually sent to every participant of the
# conversation. Zammad's article view and the Discord bot both read `to`, so
# it now always says where the message went:
#
#   SMS (RingCentral, FreePBX)  "Jane Smith (+14125550100), +14125550111"
#                               Agent replies resolve the recipients exactly
#                               like Kc::CommunicateRingcentralSmsJob and
#                               Kc::CommunicateFreepbxSmsJob do; inbound
#                               texts list the numbers the text was sent to.
#   Teams                       1:1 chat, agent side: the other person.
#                               1:1 chat, customer side: our Teams account.
#                               Group chat, either side:
#                               'Group chat "Topic" (Ann Lee, Bob Ray)'.
#   Missed calls                The number that was dialed.
#
# Teams chat details come from ticket.preferences[:teams_chat][:audience],
# which Channel::Driver::KcMicrosoftTeamsChat keeps current on every message.
# Tickets from before that existed fall back to the customer's name.
class Kc::ArticleRecipients
  SMS_TYPES = {
    'ringcentral_sms_message' => :ringcentral_sms,
    'freepbx_sms_message'     => :freepbx_sms,
  }.freeze

  TEAMS_TYPE = 'teams_chat_message'.freeze

  MISSED_CALL_KEYS = %i[freepbx_missed_call ringcentral_missed_call].freeze

  # Group chat member names shown before "+N more".
  MAX_MEMBER_NAMES = 6

  class << self
    # The `to` line for an article, or nil when there is nothing better than
    # what the article already has (email, plain notes, unknown types).
    def label_for(article)
      type_name   = Ticket::Article::Type.lookup(id: article.type_id)&.name
      sender_name = Ticket::Article::Sender.lookup(id: article.sender_id)&.name
      ticket      = article.ticket
      prefs       = indifferent(article.preferences)

      if (key = SMS_TYPES[type_name])
        sms_label(ticket, prefs[key], key, sender_name)
      elsif type_name == TEAMS_TYPE || teams_capture?(prefs)
        teams_label(ticket, sender_name, fallback: article.to)
      elsif (key = MISSED_CALL_KEYS.find { |k| prefs[k].present? })
        phone_list([indifferent(prefs[key])[:to_phone]])
      end
    rescue => e
      Rails.logger.warn "KC ArticleRecipients: no recipient label for article #{article.id || '(new)'}: #{e.message}"
      nil
    end

    # Recipient numbers of an SMS article, normalized.
    def sms_numbers(ticket, article_prefs, key, sender_name)
      article_prefs = indifferent(article_prefs)
      ticket_prefs  = indifferent(indifferent(ticket&.preferences)[key])

      list = if sender_name == 'Agent'
               # Same order as the communicate jobs.
               Array(article_prefs[:to_phones]).compact_blank.presence ||
                 Array(ticket_prefs[:participants]).compact_blank.presence ||
                 [article_prefs[:to_phone] || ticket_prefs[:from_phone]]
             else
               Array(article_prefs[:to_phones]).compact_blank.presence ||
                 [article_prefs[:to_phone] || ticket_prefs[:to_phone]]
             end
      list.compact_blank.map { |n| normalize(n) }.compact_blank.uniq
    end

    def sms_label(ticket, article_prefs, key, sender_name)
      phone_list(sms_numbers(ticket, article_prefs, key, sender_name))
    end

    # fallback: the article's own `to`, used when the chat is not known yet
    # (a chat an agent just started from Zammad names its recipient there).
    def teams_label(ticket, sender_name, fallback: nil)
      audience = indifferent(indifferent(indifferent(ticket&.preferences)[:teams_chat])[:audience])
      members  = Array(audience[:members]).compact_blank

      if audience[:chat_type].to_s == 'group'
        group_label(audience[:topic], members)
      elsif sender_name == 'Agent'
        members.join(', ').presence || fallback.presence || ticket&.customer&.fullname.presence
      else
        audience[:account_name].presence || 'Microsoft Teams'
      end
    end

    # 'Group chat "Topic" (Ann Lee, Bob Ray)'; the topic is left out when
    # Teams made it up from the member names.
    def group_label(topic, members)
      topic = topic.to_s.strip
      topic = '' if topic.count(',') >= 2

      names = members.first(MAX_MEMBER_NAMES)
      names << "+#{members.size - MAX_MEMBER_NAMES} more" if members.size > MAX_MEMBER_NAMES

      label = topic.present? ? %(Group chat "#{topic.truncate(60)}") : 'Group chat'
      names.any? ? "#{label} (#{names.join(', ')})" : label
    end

    # The audience hash stored on a Teams ticket for a chat.
    #   members: display names of everyone except our connected account
    def audience_for(chat_type:, topic:, members:, account_user_id:)
      account_user_id = account_user_id.to_s
      ours, others = Array(members).map { |m| indifferent(m) }.partition do |m|
        account_user_id.present? && m[:userId].to_s == account_user_id
      end
      {
        chat_type:    chat_type.to_s.presence,
        topic:        topic.to_s.strip.presence,
        members:      others.filter_map { |m| m[:displayName].to_s.strip.presence }.uniq,
        account_name: ours.first && ours.first[:displayName].to_s.strip.presence,
      }.compact
    end

    private

    def teams_capture?(prefs)
      indifferent(prefs[:teams_chat])[:outbound_capture].present?
    end

    def phone_list(numbers)
      numbers = Array(numbers).compact_blank
      return nil if numbers.empty?

      contacts = 'Kc::PhoneContacts'.safe_constantize
      numbers.map { |n| contacts ? contacts.display(n) : n.to_s }.join(', ')
    end

    def normalize(number)
      contacts = 'Kc::PhoneContacts'.safe_constantize
      contacts&.normalize(number) || number.to_s
    end

    def indifferent(value)
      value.respond_to?(:to_h) ? value.to_h.with_indifferent_access : {}.with_indifferent_access
    rescue
      {}.with_indifferent_access
    end
  end
end
