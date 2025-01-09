# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'net/pop'

class Channel::Driver::Pop3 < Channel::Driver::BaseEmailInbound

=begin

fetch emails from Pop3 account

  instance = Channel::Driver::Pop3.new
  result = instance.fetch(params[:inbound][:options], channel, 'verify', subject_looking_for)

returns

  {
    result: 'ok',
    fetched: 123,
    notice: 'e. g. message about to big emails in mailbox',
  }

check if connect to Pop3 account is possible, return count of mails in mailbox

  instance = Channel::Driver::Pop3.new
  result = instance.fetch(params[:inbound][:options], channel, 'check')

returns

  {
    result: 'ok',
    content_messages: 123,
  }

verify Pop3 account, check if search email is in there

  instance = Channel::Driver::Pop3.new
  result = instance.fetch(params[:inbound][:options], channel, 'verify', subject_looking_for)

returns

  {
    result: 'ok', # 'verify not ok'
  }

=end

  def fetch(options, channel)
    setup_connection(options)

    mails = @pop.mails

    # fetch regular messages
    count_all             = mails.size
    count                 = 0
    count_fetched         = 0
    too_large_messages    = []
    active_check_interval = 20
    notice                = ''
    mails.first(2000).each do |m|
      count += 1

      break if (count % active_check_interval).zero? && channel_has_changed?(channel)

      Rails.logger.info " - message #{count}/#{count_all}"
      mail = m.pop
      next if !mail

      # ignore verify messages
      if mail.match?(%r{(X-Zammad-Ignore: true|X-Zammad-Verify: true)}) && mail =~ %r{X-Zammad-Verify-Time:\s(.+?)\s}
        begin
          verify_time = Time.zone.parse($1)
          if verify_time > 30.minutes.ago
            info = "  - ignore message #{count}/#{count_all} - because it's a verify message"
            Rails.logger.info info
            next
          end
        rescue => e
          Rails.logger.error e
        end
      end

      # do not process too large messages, instead download and send postmaster reply
      max_message_size = Setting.get('postmaster_max_size').to_f
      real_message_size = mail.size.to_f / 1024 / 1024
      if real_message_size > max_message_size
        if Setting.get('postmaster_send_reject_if_mail_too_large') == true
          info = "  - download message #{count}/#{count_all} - ignore message because it's too large (is:#{real_message_size} MB/max:#{max_message_size} MB)"
          Rails.logger.info info
          notice += "#{info}\n"
          process_oversized_mail(channel, mail)
        else
          info = "  - ignore message #{count}/#{count_all} - because message is too large (is:#{real_message_size} MB/max:#{max_message_size} MB)"
          Rails.logger.info info
          notice += "#{info}\n"
          too_large_messages.push info
          next
        end

      # delete email from server after article was created
      else
        process(channel, m.pop, false)
      end

      m.delete
      count_fetched += 1
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

    Rails.logger.info 'done'
    {
      result:  'ok',
      fetched: count_fetched,
      notice:  notice,
    }
  end

  def check(options)
    setup_connection(options, check: true)

    mails = @pop.mails

    Rails.logger.info 'check only mode, fetch no emails'
    content_max_check = 2
    content_messages  = 0

    # check messages
    mails.each do |m|
      mail = m.pop
      next if !mail

      # check how many content messages we have, for notice used
      if !mail.match?(%r{(X-Zammad-Ignore: true|X-Zammad-Verify: true)})
        content_messages += 1
        break if content_max_check < content_messages
      end
    end
    if content_messages >= content_max_check
      content_messages = mails.count
    end
    disconnect

    {
      result:           'ok',
      content_messages: content_messages,
    }
  end

  def verify(options, verify_string)
    setup_connection(options)

    mails = @pop.mails

    Rails.logger.info 'verify mode, fetch no emails'
    mails.reverse!

    # check for verify message
    mails.first(2000).each do |m|
      mail = m.pop
      next if !mail

      # check if verify message exists
      next if !mail.match?(%r{#{verify_string}})

      Rails.logger.info " - verify email #{verify_string} found"
      m.delete
      disconnect
      return {
        result: 'ok',
      }
    end

    {
      result: 'verify not ok',
    }
  end

  def disconnect
    return if !@pop

    @pop.finish
  end

  def setup_connection(options, check: false)
    ssl = true
    if options[:ssl] == 'off'
      ssl = false
    end
    ssl_verify = options.fetch(:ssl_verify, true)

    port = if options.key?(:port) && options[:port].present?
             options[:port].to_i
           elsif ssl == true
             995
           else
             110
           end

    Rails.logger.info "fetching pop3 (#{options[:host]}/#{options[:user]} port=#{port},ssl=#{ssl})"

    @pop = ::Net::POP3.new(options[:host], port)
    # @pop.set_debug_output $stderr

    # on check, reduce open_timeout to have faster probing
    if check
      @pop.open_timeout = 4
      @pop.read_timeout = 6
    else
      @pop.open_timeout = 16
      @pop.read_timeout = 45
    end

    if ssl
      Certificate::ApplySSLCertificates.ensure_fresh_ssl_context
      @pop.enable_ssl((ssl_verify ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE))
    end
    @pop.start(options[:user], options[:password])
  end

end
