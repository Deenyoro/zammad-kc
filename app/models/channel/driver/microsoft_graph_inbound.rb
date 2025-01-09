# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class Channel::Driver::MicrosoftGraphInbound < Channel::Driver::BaseEmailInbound

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

  def fetch(options, channel) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    setup_connection(options)

    keep_on_server = ActiveModel::Type::Boolean.new.cast(options[:keep_on_server])

    if options[:folder_id].present?
      folder_id = options[:folder_id]
      verify_folder!(folder_id, options)
    end

    # Taking first page of messages only effectivelly applies 1000-messages-in-one-go limit
    begin
      message_ids = @graph
        .list_messages(unread_only: keep_on_server, folder_id:, follow_pagination: false)
        .pluck(:id)
    rescue MicrosoftGraph::ApiError => e
      Rails.logger.error "Unable to list emails from Microsoft Graph server (#{options[:user]}): #{e.inspect}"
      raise e
    end

    # fetch regular messages
    count_all             = message_ids.count
    count                 = 0
    count_fetched         = 0
    too_large_messages    = []
    active_check_interval = 20
    result                = 'ok'
    notice                = ''
    message_ids.each do |message_id| # rubocop:disable Metrics/BlockLength
      count += 1

      break if (count % active_check_interval).zero? && channel_has_changed?(channel)

      Rails.logger.info " - message #{count}/#{count_all}"

      message_meta = @graph.get_message_basic_details(message_id)

      next if message_meta.nil?

      # ignore verify messages
      next if !messages_is_too_old_verify?(message_meta[:headers], count, count_all)

      # ignore already imported
      if already_imported?(message_meta[:headers], keep_on_server, channel)
        begin
          @graph.mark_message_as_read(message_id)
          Rails.logger.info "Ignore message #{count}/#{count_all}, because message message id already imported. Graph API Message ID: #{message_id}."
        rescue MicrosoftGraph::ApiError => e
          Rails.logger.error "Unable to mark email as read #{count}/#{count_all} from Microsoft Graph server (#{options[:user]}). Graph API Message ID: #{message_id}. #{e.inspect}"
          raise e
        end

        next
      end

      # delete email from server after article was created
      begin
        msg = @graph.get_raw_message(message_id)
      rescue MicrosoftGraph::ApiError => e
        Rails.logger.error "Unable to fetch email #{count}/#{count_all} from Microsoft Graph server (#{options[:user]}). Graph API Message ID: #{message_id}. #{e.inspect}"
        raise e
      end

      # do not process too big messages, instead download & send postmaster reply
      too_large_info = too_large?(message_meta[:size])
      if too_large_info
        if Setting.get('postmaster_send_reject_if_mail_too_large') == true
          info = "  - download message #{count}/#{count_all} - ignore message because it's too large (is:#{too_large_info[0]} MB/max:#{too_large_info[1]} MB) - Graph API Message ID: #{message_id}"
          Rails.logger.info info
          notice += "#{info}\n"
          process_oversized_mail(channel, msg)
        else
          info = "  - ignore message #{count}/#{count_all} - because message is too large (is:#{too_large_info[0]} MB/max:#{too_large_info[1]} MB) - Graph API Message ID: #{message_id}"
          Rails.logger.info info
          notice += "#{info}\n"
          too_large_messages.push info
          next
        end
      else
        process(channel, msg, false)
      end

      if keep_on_server
        begin
          @graph.mark_message_as_read(message_id)
        rescue MicrosoftGraph::ApiError => e
          Rails.logger.error "Unable to mark email as read #{count}/#{count_all} from Microsoft Graph server (#{options[:user]}). Graph API Message ID: #{message_id}. #{e.inspect}"
          raise e
        end
      else
        begin
          @graph.delete_message(message_id)
        rescue MicrosoftGraph::ApiError => e
          Rails.logger.error "Unable to delete #{count}/#{count_all} from Microsoft Graph server (#{options[:user]}). Graph API Message ID: #{message_id}. #{e.inspect}"
          raise e
        end
      end

      count_fetched += 1
    end

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

  def check(options)
    setup_connection(options)

    Rails.logger.info 'check only mode, fetch no emails'

    if options[:folder_id].present?
      folder_id = options[:folder_id]
      verify_folder!(folder_id, options)
    end

    # Simply try to list messages
    # This will check if mailbox access is possible with the given credentials
    begin
      @graph.list_messages folder_id:, follow_pagination: false
    rescue MicrosoftGraph::ApiError => e
      Rails.logger.error "Unable to list emails from Microsoft Graph server (#{options[:user]}): #{e.inspect}"
      raise e
    end

    # Microsoft Graph API driver currently does not use archivation.
    # Just like other OAuth channels (Google and Microsoft 365 IMAP).
    # Once archivation is brought to Microsoft Graph API,
    # it could be implemented with an API call checking if old messages are present in the mailbox.

    {
      result:                       'ok',
      archive_possible:             false,
      archive_possible_is_fallback: false,
    }
  end

  def verify(_options, _verify_string)
    raise 'Microsoft Graph email channel is never verified. Thus this method is not implemented.' # rubocop:disable Zammad/DetectTranslatableString
  end

  private

  def setup_connection(options)
    access_token = options[:password]
    mailbox      = options[:shared_mailbox].presence || options[:user]

    @graph = MicrosoftGraph.new access_token:, mailbox:
  end

  def verify_folder!(id, options)
    @graph.get_message_folder_details(id)
  rescue MicrosoftGraph::ApiError => e
    raise e if e.error_code != 'ErrorInvalidIdMalformed'

    Rails.logger.error "Unable to fetch email from folder at Microsoft Graph/#{options[:user]} Folder does not exist: #{id}"
    raise "Microsoft Graph email folder does not exist: #{id}"
  end
end
