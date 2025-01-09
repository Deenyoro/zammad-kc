# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class Channel::Driver::BaseEmailInbound < Channel::EmailParser
  def fetch(_options, _channel)
    raise 'not implemented'
  end

  def check(_options)
    raise 'not implemented'
  end

  def verify(_options, _verify_string)
    raise 'not implemented'
  end

  def fetchable?(_channel)
    true
  end

  def self.streamable?
    false
  end

  # Checks if the given channel was modified since it it was loaded
  # This check is used in email fetching loop
  def channel_has_changed?(channel)
    current_channel = Channel.find_by(id: channel.id)
    if !current_channel
      Rails.logger.info "Channel with id #{channel.id} is deleted in the meantime. Stop fetching."
      return true
    end
    return false if channel.updated_at == current_channel.updated_at

    Rails.logger.info "Channel with id #{channel.id} has changed. Stop fetching."
    true
  end

  # Checks if email is not too big for processing
  #
  # @param [Integer] size in bytes
  #
  # This method is used by IMAP and MicrosoftGraphInbound only
  # It may be possible to reuse them with POP3 too, but it needs further refactoring
  def too_large?(message_meta_size)
    max_message_size = Setting.get('postmaster_max_size').to_f
    real_message_size = message_meta_size.to_f / 1024 / 1024
    if real_message_size > max_message_size
      return [real_message_size, max_message_size]
    end

    false
  end

  # Checks if a message with the given headers is a Zammad verify message
  #
  # This method is used by IMAP and MicrosoftGraphInbound only
  # It may be possible to reuse them with POP3 too, but it needs further refactoring
  def messages_is_verify_message?(headers)
    return true if headers['X-Zammad-Verify'] == 'true'

    false
  end

  # Checks if a message with the given headers marked to be ignored by Zammad
  #
  # This method is used by IMAP and MicrosoftGraphInbound only
  # It may be possible to reuse them with POP3 too, but it needs further refactoring
  def messages_is_ignore_message?(headers)
    return true if headers['X-Zammad-Ignore'] == 'true'

    false
  end

  # Checks if a message is an old Zammad verify message
  #
  # Returns false only if a verify message is less than 30 minutes old
  #
  # This method is used by IMAP and MicrosoftGraphInbound only
  # It may be possible to reuse them with POP3 too, but it needs further refactoring
  def messages_is_too_old_verify?(headers, count, count_all)
    return true if !messages_is_verify_message?(headers)
    return true if headers['X-Zammad-Verify-Time'].blank?

    begin
      verify_time = Time.zone.parse(headers['X-Zammad-Verify-Time'])
    rescue => e
      Rails.logger.error e
      return true
    end
    return true if verify_time < 30.minutes.ago

    Rails.logger.info "  - ignore message #{count}/#{count_all} - because message has a verify message"

    false
  end

  # Checks if a message is already imported in a given channel
  # This check is skipped for channels which do not keep messages on the server
  #
  # This method is used by IMAP and MicrosoftGraphInbound only
  # It may be possible to reuse them with POP3 too, but it needs further refactoring
  def already_imported?(headers, keep_on_server, channel)
    return false if !keep_on_server

    return false if !headers

    local_message_id = headers['Message-ID']
    return false if local_message_id.blank?

    local_message_id_md5 = Digest::MD5.hexdigest(local_message_id)
    article = Ticket::Article.where(message_id_md5: local_message_id_md5).reorder('created_at DESC, id DESC').limit(1).first
    return false if !article

    # verify if message is already imported via same channel, if not, import it again
    ticket = article.ticket
    return false if ticket&.preferences && ticket.preferences[:channel_id].present? && channel.present? && ticket.preferences[:channel_id] != channel[:id]

    true
  end
end
