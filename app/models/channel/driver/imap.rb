# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'net/imap'

class Channel::Driver::Imap < Channel::Driver::BaseEmailInbound

  FETCH_METADATA_TIMEOUT = 2.minutes
  FETCH_MSG_TIMEOUT = 4.minutes
  EXPUNGE_TIMEOUT = 16.minutes
  DEFAULT_TIMEOUT = 45.seconds
  CHECK_ONLY_TIMEOUT = 8.seconds

=begin

fetch emails from IMAP account

  instance = Channel::Driver::Imap.new
  result = instance.fetch(params[:inbound][:options], channel, 'verify', subject_looking_for)

returns

  {
    result: 'ok',
    fetched: 123,
    notice: 'e. g. message about to big emails in mailbox',
  }

check if connect to IMAP account is possible, return count of mails in mailbox

  instance = Channel::Driver::Imap.new
  result = instance.fetch(params[:inbound][:options], channel, 'check')

returns

  {
    result: 'ok',
    content_messages: 123,
  }

verify IMAP account, check if search email is in there

  instance = Channel::Driver::Imap.new
  result = instance.fetch(params[:inbound][:options], channel, 'verify', subject_looking_for)

returns

  {
    result: 'ok', # 'verify not ok'
  }

example

  params = {
    host: 'outlook.office365.com',
    user: 'xxx@zammad.onmicrosoft.com',
    password: 'xxx',
    keep_on_server: true,
  }

  OR

  params = {
    host: 'imap.gmail.com',
    user: 'xxx@gmail.com',
    password: 'xxx',
    keep_on_server: true,
    auth_type: 'XOAUTH2'
  }

  channel = Channel.last
  instance = Channel::Driver::Imap.new
  result = instance.fetch(params, channel, 'verify')

=end

  def fetch(options, channel)
    setup_connection(options)

    keep_on_server = false
    if [true, 'true'].include?(options[:keep_on_server])
      keep_on_server = true
    end

    message_ids_result = Timeout.timeout(6.minutes) do
      if keep_on_server
        fetch_unread_message_ids
      else
        fetch_all_message_ids
      end
    end

    message_ids = message_ids_result[:result]

    # fetch regular messages
    count_all             = message_ids.count
    count                 = 0
    count_fetched         = 0
    count_max             = 5000
    too_large_messages    = []
    active_check_interval = 20
    result                = 'ok'
    notice                = ''
    message_ids.each do |message_id|
      count += 1

      break if (count % active_check_interval).zero? && channel_has_changed?(channel)
      break if max_process_count_was_reached?(channel, count, count_max)

      Rails.logger.info " - message #{count}/#{count_all}"

      message_meta = nil
      Timeout.timeout(FETCH_METADATA_TIMEOUT) do
        message_meta = @imap.fetch(message_id, ['RFC822.SIZE', 'FLAGS', 'INTERNALDATE', 'RFC822.HEADER'])[0]
      rescue Net::IMAP::ResponseParseError => e
        raise if e.message.exclude?('unknown token')

        result = 'error'
        notice += <<~NOTICE
          One of your incoming emails could not be imported (#{e.message}).
          Please remove it from your inbox directly
          to prevent Zammad from trying to import it again.
        NOTICE
        Rails.logger.error "Net::IMAP failed to parse message #{message_id}: #{e.message} (#{e.class})"
        Rails.logger.error '(See https://github.com/zammad/zammad/issues/2754 for more details)'
      end

      next if message_meta.nil?

      # ignore verify messages
      next if !messages_is_too_old_verify?(self.class.extract_rfc822_headers(message_meta), count, count_all)

      # ignore deleted messages
      next if deleted?(message_meta, count, count_all)

      # ignore already imported
      if already_imported?(self.class.extract_rfc822_headers(message_meta), keep_on_server, channel)
        Timeout.timeout(1.minute) do
          @imap.store(message_id, '+FLAGS', [:Seen])
        end
        Rails.logger.info "  - ignore message #{count}/#{count_all} - because message message id already imported"

        next
      end

      # delete email from server after article was created
      msg = nil
      begin
        Timeout.timeout(FETCH_MSG_TIMEOUT) do
          key = fetch_message_body_key(options)
          msg = @imap.fetch(message_id, key)[0].attr[key]
        end
      rescue Timeout::Error => e
        Rails.logger.error "Unable to fetch email from #{count}/#{count_all} from server (#{options[:host]}/#{options[:user]}): #{e.inspect}"
        raise e
      end
      next if !msg

      # do not process too big messages, instead download & send postmaster reply
      too_large_info = too_large?(message_meta.attr['RFC822.SIZE'])
      if too_large_info
        if Setting.get('postmaster_send_reject_if_mail_too_large') == true
          info = "  - download message #{count}/#{count_all} - ignore message because it's too large (is:#{too_large_info[0]} MB/max:#{too_large_info[1]} MB)"
          Rails.logger.info info
          notice += "#{info}\n"
          process_oversized_mail(channel, msg)
        else
          info = "  - ignore message #{count}/#{count_all} - because message is too large (is:#{too_large_info[0]} MB/max:#{too_large_info[1]} MB)"
          Rails.logger.info info
          notice += "#{info}\n"
          too_large_messages.push info
          next
        end
      else
        process(channel, msg, false)
      end

      begin
        Timeout.timeout(FETCH_MSG_TIMEOUT) do
          if keep_on_server
            @imap.store(message_id, '+FLAGS', [:Seen])
          else
            @imap.store(message_id, '+FLAGS', [:Deleted])
          end
        end
      rescue Timeout::Error => e
        Rails.logger.error "Unable to set +FLAGS for email #{count}/#{count_all} on server (#{options[:host]}/#{options[:user]}): #{e.inspect}"
        raise e
      end
      count_fetched += 1
    end

    if !keep_on_server
      begin
        Timeout.timeout(EXPUNGE_TIMEOUT) do
          @imap.expunge
        end
      rescue Timeout::Error => e
        Rails.logger.error "Unable to expunge server (#{options[:host]}/#{options[:user]}): #{e.inspect}"
        raise e
      end
    end
    disconnect
    if count.zero?
      Rails.logger.info ' - no message'
    end

    # Error is raised if one of the messages was too large AND postmaster_send_reject_if_mail_too_large is turned off.
    # This effectivelly marks channels as stuck and gets highlighted for the admin.
    # New emails are still processed! But large email is not touched, so error keeps being re-raised on every fetch.
    if too_large_messages.present?
      raise too_large_messages.join("\n")
    end

    {
      result:  result,
      fetched: count_fetched,
      notice:  notice,
    }
  end

  # Checks if mailbox has anything besides Zammad verification emails.
  # If any real messages exists, return the real count including messages to be ignored when importing.
  # If only verification messages found, return 0.
  def check_configuration(options)
    setup_connection(options, check: true)

    message_ids_result = Timeout.timeout(6.minutes) do
      fetch_all_message_ids
    end

    message_ids = message_ids_result[:result]

    Rails.logger.info 'check only mode, fetch no emails'

    has_content_messages = message_ids
      .first(5000)
      .any? do |message_id|
        message_meta = Timeout.timeout(1.minute) do
          @imap.fetch(message_id, ['RFC822.HEADER'])[0]
        end

        # check how many content messages we have, for notice used
        headers = self.class.extract_rfc822_headers(message_meta)

        !messages_is_verify_message?(headers) && !messages_is_ignore_message?(headers)
      end

    disconnect

    {
      result:           'ok',
      content_messages: has_content_messages ? message_ids.count : 0,
    }
  end

  # This method is used for custom IMAP only.
  # It is not used in conjunction with Micrsofot365 or Gogle OAuth channels.
  def verify(options, verify_string)
    setup_connection(options)

    message_ids_result = Timeout.timeout(6.minutes) do
      fetch_all_message_ids
    end

    message_ids = message_ids_result[:result]

    Rails.logger.info "verify mode, fetch no emails #{verify_string}"

    # check for verify message
    message_ids.reverse_each do |message_id|

      message_meta = nil
      Timeout.timeout(FETCH_METADATA_TIMEOUT) do
        message_meta = @imap.fetch(message_id, ['RFC822.HEADER'])[0]
      end

      # check if verify message exists
      headers = self.class.extract_rfc822_headers(message_meta)
      subject = headers['Subject']
      next if !subject
      next if !subject.match?(%r{#{verify_string}})

      Rails.logger.info " - verify email #{verify_string} found"
      Timeout.timeout(600) do
        @imap.store(message_id, '+FLAGS', [:Deleted])
        @imap.expunge
      end
      disconnect
      return {
        result: 'ok',
      }
    end

    disconnect
    {
      result: 'verify not ok',
    }
  end

  def fetch_all_message_ids
    fetch_message_ids %w[ALL]
  end

  def fetch_unread_message_ids
    fetch_message_ids %w[NOT SEEN]
  rescue
    fetch_message_ids %w[UNSEEN]
  end

  def fetch_message_ids(filter)
    raise if @imap.capabilities.exclude?('SORT')

    {
      result:      @imap.sort(['DATE'], filter, 'US-ASCII'),
      is_fallback: false
    }
  rescue
    {
      result:      @imap.search(filter),
      is_fallback: true # indicates that we can not use a result ordered by date
    }
  end

  def fetch_message_body_key(options)
    # https://github.com/zammad/zammad/issues/4589
    options['host'] == 'imap.mail.me.com' ? 'BODY[]' : 'RFC822'
  end

  def disconnect
    return if !@imap

    Timeout.timeout(1.minute) do
      @imap.disconnect
    end
  end

  # Parses RFC822 header
  # @param [String] RFC822 header text blob
  # @return [Hash<String=>String>]
  def self.parse_rfc822_headers(string)
    array = string
              .gsub("\r\n\t", ' ') # Some servers (e.g. microsoft365) may put attribute value on a separate line and tab it
              .lines(chomp: true)
              .map { |line| line.split(%r{:\s*}, 2).map(&:strip) }

    array.each { |elem| elem.append(nil) if elem.one? }

    Hash[*array.flatten]
  end

  # Parses RFC822 header
  # @param [Net::IMAP::FetchData] fetched message
  # @return [Hash<String=>String>]
  def self.extract_rfc822_headers(message_meta)
    blob = message_meta&.attr&.dig 'RFC822.HEADER'

    return if !blob

    parse_rfc822_headers blob
  end

  private

=begin

check if email is already marked as deleted

  Channel::Driver::IMAP.deleted?(message_meta, count, count_all)

returns

  true|false

=end

  def deleted?(message_meta, count, count_all)
    return false if message_meta.attr['FLAGS'].exclude?(:Deleted)

    Rails.logger.info "  - ignore message #{count}/#{count_all} - because message has already delete flag"
    true
  end

=begin

check if maximal fetching email count has reached

  Channel::Driver::IMAP.max_process_count_was_reached?(channel, count, count_max)

returns

  true|false

=end

  def max_process_count_was_reached?(channel, count, count_max)
    return false if count < count_max

    Rails.logger.info "Maximal fetched emails (#{count_max}) reached for this interval for Channel with id #{channel.id}."
    true
  end

  def setup_connection(options, check: false)
    ssl            = true
    ssl_verify     = options.fetch(:ssl_verify, true)
    starttls       = false
    keep_on_server = false
    folder         = 'INBOX'
    if [true, 'true'].include?(options[:keep_on_server])
      keep_on_server = true
    end

    case options[:ssl]
    when 'off'
      ssl = false
    when 'starttls'
      ssl = false
      starttls = true
    end

    port = if options.key?(:port) && options[:port].present?
             options[:port].to_i
           elsif ssl == true
             993
           else
             143
           end

    if options[:folder].present?
      folder = options[:folder]
    end

    Rails.logger.info "fetching imap (#{options[:host]}/#{options[:user]} port=#{port},ssl=#{ssl},starttls=#{starttls},folder=#{folder},keep_on_server=#{keep_on_server},auth_type=#{options.fetch(:auth_type, 'LOGIN')})"

    # on check, reduce open_timeout to have faster probing
    check_type_timeout = check ? CHECK_ONLY_TIMEOUT : DEFAULT_TIMEOUT

    Certificate::ApplySSLCertificates.ensure_fresh_ssl_context if ssl || starttls

    Timeout.timeout(check_type_timeout) do
      ssl_settings = false
      ssl_settings = (ssl_verify ? true : { verify_mode: OpenSSL::SSL::VERIFY_NONE }) if ssl
      @imap = ::Net::IMAP.new(options[:host], port: port, ssl: ssl_settings)
      if starttls
        @imap.starttls(verify_mode: ssl_verify ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE)
      end
    end

    Timeout.timeout(check_type_timeout) do
      if options[:auth_type].present?
        @imap.authenticate(options[:auth_type], options[:user], options[:password])
      else
        @imap.login(options[:user], options[:password].dup&.force_encoding('ascii-8bit'))
      end
    end

    Timeout.timeout(check_type_timeout) do
      # select folder
      @imap.select(folder)
    end
  end
end
