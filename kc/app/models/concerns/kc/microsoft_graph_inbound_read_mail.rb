# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# KC: Import Microsoft 365 (Graph) mail that someone already read in Outlook.
#
# PROBLEM:
# With "keep messages on server" upstream lists only unread inbox messages
# (MicrosoftGraph#list_messages adds `isRead eq false`). A message that an
# agent opens in Outlook before the next fetch is never imported (ticket
# 188698: the customer's original email was skipped, only a CC'd reply came
# in).
#
# FIX:
# After upstream's unread list, also list the READ messages of the same folder
# received within a recent window (KC_GRAPH_READ_MAIL_WINDOW_HOURS, default
# 72, 0 switches this off) and hand those whose Message-ID matches no existing
# article to upstream's fetch_single_message, which imports and marks them as
# read like any other message.
#
# HARDENING:
# 1. Only with keep_on_server (without it upstream lists read mail already and
#    deletes after import) and only during a real fetch (@channel set), never
#    for check_configuration.
# 2. Read mail is skipped when ANY article already has its Message-ID, which
#    is stricter than upstream's already_imported? (that one re-imports mail
#    first seen through another channel). So mail Zammad itself sent and
#    already holds is never imported again.
# 3. Every Graph message id that went through fetch_single_message is
#    remembered in Rails.cache (memcached) for the window plus a day, so mail
#    whose ticket was later deleted, or that a postmaster filter ignored, is
#    not imported again on every fetch.
# 4. The window lists at most READ_MAIL_MAX_PAGES * READ_MAIL_PAGE_SIZE
#    messages, oldest first. A failure in the KC part is logged and the fetch
#    continues with upstream's unread list only.
# 5. Boot-time fingerprint check: if upstream rewrites messages_iterator or
#    fetch_single_message the log says so (the overlay may then be dead or
#    double-listing).
module Kc
  module MicrosoftGraphInboundReadMail
    extend ActiveSupport::Concern

    UPSTREAM_FILE = 'app/models/channel/driver/microsoft_graph_inbound.rb'.freeze

    UPSTREAM_FINGERPRINT = [
      'def messages_iterator(keep_on_server, options)',
      'list_messages(unread_only: keep_on_server',
      'def fetch_single_message(message_id, count, count_all)',
      'already_imported?(@keep_on_server, @channel)',
      '@graph.mark_message_as_read(message_id)',
    ].freeze

    WINDOW_ENV          = 'KC_GRAPH_READ_MAIL_WINDOW_HOURS'.freeze
    DEFAULT_WINDOW      = 72
    MAX_WINDOW          = 14 * 24
    READ_MAIL_PAGE_SIZE = 100
    READ_MAIL_MAX_PAGES = 10

    prepended do
      check_upstream_read_mail_fingerprint
    end

    class_methods do
      def check_upstream_read_mail_fingerprint
        upstream_file = Rails.root.join(UPSTREAM_FILE)
        return if !File.exist?(upstream_file)

        source  = File.read(upstream_file)
        missing = UPSTREAM_FINGERPRINT.reject { |needle| source.include?(needle) }

        if missing.empty?
          Rails.logger.info "KC: MicrosoftGraphInboundReadMail, upstream messages_iterator unchanged, override is ACTIVE (window #{kc_read_mail_window_hours}h)."
        else
          Rails.logger.warn 'KC: MicrosoftGraphInboundReadMail, UPSTREAM messages_iterator/fetch_single_message CHANGED ' \
                            "(missing: #{missing.join(' | ')}). Review " \
                            'kc/app/models/concerns/kc/microsoft_graph_inbound_read_mail.rb against ' \
                            "#{UPSTREAM_FILE}."
        end
      rescue => e
        Rails.logger.warn "KC: MicrosoftGraphInboundReadMail, failed to check upstream: #{e.message}"
      end

      def kc_read_mail_window_hours
        raw = ENV[WINDOW_ENV].to_s.strip
        return DEFAULT_WINDOW if raw.empty?
        return DEFAULT_WINDOW if !raw.match?(%r{\A\d+\z})

        [raw.to_i, MAX_WINDOW].min
      end
    end

    def messages_iterator(keep_on_server, options)
      ids, count = super
      return [ids, count] if !kc_read_mail_active?(keep_on_server)

      extra = kc_read_mail_candidates(options, ids)
      if extra.any?
        Rails.logger.info "KC: MicrosoftGraphInboundReadMail, #{extra.size} already-read message(s) not imported yet, fetching them"
      end

      [ids + extra, count + extra.size]
    end

    def fetch_single_message(message_id, count, count_all)
      result = super
      kc_read_mail_remember(message_id) if kc_read_mail_active?(@keep_on_server) && !kc_read_mail_retry?(result)
      result
    end

    # Read messages within the window that should be imported. Public so a
    # dry run can call it after setup_connection.
    def kc_read_mail_candidates(options, exclude_ids = [])
      exclude = exclude_ids.to_set

      kc_read_mail_list(options).filter_map do |item|
        id = item[:id]
        next if id.blank? || exclude.include?(id)
        next if kc_read_mail_remembered?(id)

        if kc_read_mail_imported?(item[:internetMessageId])
          kc_read_mail_remember(id)
          next
        end

        id
      end
    rescue => e
      Rails.logger.error "KC: MicrosoftGraphInboundReadMail, listing read mail failed, continuing with unread only: #{e.class}: #{e.message}"
      []
    end

    def kc_read_mail_list(options)
      folder = options[:folder_id].presence || 'inbox'
      since  = (Time.zone.now - self.class.kc_read_mail_window_hours.hours).utc.iso8601
      # Graph requires $orderby properties to lead the $filter.
      filter = "receivedDateTime ge #{since} and isRead eq true"
      query  = {
        '$filter'  => filter,
        '$orderby' => 'receivedDateTime asc',
        '$select'  => 'id,internetMessageId,receivedDateTime',
        '$top'     => READ_MAIL_PAGE_SIZE,
      }.to_query
      path = "mailFolders/#{ERB::Util.url_encode(folder)}/messages?#{query}"

      items = []
      READ_MAIL_MAX_PAGES.times do
        response = @graph.send(:make_request, path)
        items.concat(Array(response[:value] || response['value']))
        path = response[:'@odata.nextLink'] || response['@odata.nextLink']
        break if path.blank?
      end
      items.map { |item| item.to_h.with_indifferent_access }
    end

    private

    def kc_read_mail_active?(keep_on_server)
      ActiveModel::Type::Boolean.new.cast(keep_on_server) &&
        @channel.present? &&
        self.class.kc_read_mail_window_hours.positive?
    end

    def kc_read_mail_imported?(internet_message_id)
      # Without a Message-ID the import cannot be recognised later: skip
      # rather than re-import on every fetch.
      return true if internet_message_id.blank?

      Ticket::Article.exists?(message_id_md5: Digest::MD5.hexdigest(internet_message_id))
    end

    # Upstream leaves a message for the next run when processing failed.
    def kc_read_mail_retry?(result)
      action = result.respond_to?(:after_action) ? result.after_action : nil
      action.is_a?(Array) && action.first == :result_error
    end

    def kc_read_mail_cache_key(message_id)
      "kc:graph_read_mail:#{@channel&.id}:#{Digest::MD5.hexdigest(message_id.to_s)}"
    end

    def kc_read_mail_remembered?(message_id)
      Rails.cache.read(kc_read_mail_cache_key(message_id)).present?
    rescue => e
      Rails.logger.warn "KC: MicrosoftGraphInboundReadMail, cache read failed: #{e.message}"
      false
    end

    def kc_read_mail_remember(message_id)
      Rails.cache.write(kc_read_mail_cache_key(message_id), 1, expires_in: (self.class.kc_read_mail_window_hours + 24).hours)
    rescue => e
      Rails.logger.warn "KC: MicrosoftGraphInboundReadMail, cache write failed: #{e.message}"
    end
  end
end
