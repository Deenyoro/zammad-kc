# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# KC: Ticket titles for Microsoft Teams chats.
#
# A group or meeting chat is named like Teams names it: its topic, or the
# members' names when nobody set one (Graph returns topic null then). The old
# fallback "Group Chat #<last 8 characters of the chat id>" always read
# "Group Chat #hread.v2", because every chat id ends in "@thread.v2".
#
# Titles the integration generated are remembered in
# ticket.preferences[:teams_chat][:auto_title] and kept in sync with the
# chat's topic and members. A title an agent typed is never overwritten.
module Kc
  module TeamsChatTitle
    GROUP_TYPES = %w[group meeting].freeze
    DEFAULT_TEMPLATE       = 'Teams Message from {user_name}'.freeze
    DEFAULT_GROUP_TEMPLATE = 'Teams group chat: {chat_name}'.freeze
    MAX_MEMBER_NAMES = 4
    MAX_LENGTH       = 100

    # Titles of tickets created before 0.0.17 that may be replaced.
    LEGACY_GROUP_TITLE = /Group Chat #\S{1,8}\z/

    module_function

    def group?(chat_type)
      GROUP_TYPES.include?(chat_type.to_s)
    end

    # The chat's name, or nil for a 1:1 chat or when nothing is known.
    #   members: Graph conversationMember hashes (displayName, userId) or names
    def chat_name(chat_type:, topic:, members:, account_user_id: nil)
      return nil unless group?(chat_type)

      topic = topic.to_s.strip
      return topic if topic.present?

      names = member_names(members, account_user_id)
      return nil if names.empty?

      listed = names.first(MAX_MEMBER_NAMES)
      listed << "+#{names.size - MAX_MEMBER_NAMES} more" if names.size > MAX_MEMBER_NAMES
      listed.join(', ')
    end

    def member_names(members, account_user_id = nil)
      account_user_id = account_user_id.to_s
      Array(members).filter_map do |member|
        if member.is_a?(String)
          member.strip.presence
        else
          m = member.to_h.with_indifferent_access
          next if account_user_id.present? && m[:userId].to_s == account_user_id

          m[:displayName].to_s.strip.presence
        end
      end.uniq
    end

    def group_title(chat_name, template: nil)
      template = template.to_s.presence || DEFAULT_GROUP_TEMPLATE
      template = DEFAULT_GROUP_TEMPLATE unless template.include?('{chat_name}')
      template.gsub('{chat_name}', chat_name.to_s).truncate(MAX_LENGTH, omission: '...')
    end

    def person_title(name, template: nil)
      template = template.to_s.presence || DEFAULT_TEMPLATE
      template.gsub('{user_name}', name.to_s).truncate(MAX_LENGTH, omission: '...')
    end

    # True when the current title is one the integration generated and may be
    # replaced: the remembered auto title, a legacy "Group Chat #..." title,
    # or (for tickets from before titles were remembered) the 1:1 template
    # applied to someone's name, which the first group message produced.
    def replaceable?(current_title, auto_title: nil, template: nil)
      current = current_title.to_s.strip
      return true if current.empty?
      return true if auto_title.present? && current == auto_title.to_s.strip
      return true if current.match?(LEGACY_GROUP_TITLE)
      return false if auto_title.present?

      prefix = (template.to_s.presence || DEFAULT_TEMPLATE).split('{user_name}').first.to_s
      prefix.present? && current.start_with?(prefix)
    end
  end
end
