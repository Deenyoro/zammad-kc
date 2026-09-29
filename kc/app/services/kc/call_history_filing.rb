# KC: Files phone calls as closed tickets so phone activity counts toward
# per-customer and per-organization reporting.
#
# Shared by the RingCentral and FreePBX history jobs. A call is one closed
# "phone" ticket, backdated to the call's start, keyed by a per-source
# message_id on its article. Filing is an upsert: a record that RingCentral
# later finalizes with a different result, duration or party updates the
# ticket in place instead of leaving the first, preliminary, version behind.
#
# Tickets filed here are records, not work: triggers and agent notifications
# are disabled around every write so nothing pages Discord or emails agents.
#
# Text-thread call notes (kc_ringcentral_sms_call_thread_notes): a call to
# or from a number that has an open SMS ticket is also written to that
# ticket as an internal note, so the thread shows every call on the number
# alongside the texts. The note never changes the ticket's state, and a
# closed thread gets nothing.
module Kc::CallHistoryFiling
  DISPATCH_DISABLE = ['Transaction::Trigger', 'Transaction::Notification'].freeze

  THREAD_NOTE_PREFIX = 'kc_call_note:'.freeze

  # Numbers that belong to us: every RingCentral number in the system plus
  # anything the caller passes in (forwarding targets seen in call legs,
  # the PBX DID). A call "to" or "from" one of these is never a customer
  # record.
  def own_numbers(extra = [])
    @own_numbers ||= begin
      list = Array(Kc::OutboundSms.available_numbers).map { |n| n.is_a?(Hash) ? (n[:number] || n['number']) : n }
      list.map { |n| normalize_number(n) }.compact.to_set
    end
    extra.each { |n| (n = normalize_number(n)) && @own_numbers << n }
    @own_numbers
  end

  def own_number?(number)
    n = normalize_number(number)
    n.present? && own_numbers.include?(n)
  end

  def normalize_number(number)
    return nil if number.blank?

    rc = 'Kc::RingcentralApi'.safe_constantize
    rc ? rc.normalize_phone(number) : number.to_s
  end

  # Files or updates one call. Returns :created, :updated or :unchanged.
  #
  # dedup_key  article message_id, e.g. "rc_call:<sessionId>"
  # external   the customer's number in E.164 (ticket customer + title)
  # outcome    human label, e.g. "Answered on FreePBX by ext 201 (Dean)"
  # line       second body line, e.g. "+1412... → +1412..."
  # prefs      hash stored under prefs_key on the ticket; compared for change
  def file_call_record(dedup_key:, channel:, external:, inbound:, start_time:, duration:, outcome:, line:, prefs_key:, prefs:)
    transaction_class = 'Transaction'.safe_constantize
    raise 'Transaction class not found' if transaction_class.nil?

    article = Ticket::Article.find_by(message_id: dedup_key)
    body = [
      "#{inbound ? 'Inbound' : 'Outbound'} call — #{outcome}",
      line,
      "Time: #{start_time.in_time_zone.strftime('%Y-%m-%d %H:%M')}  Duration: #{format('%d:%02d', duration / 60, duration % 60)}",
    ].join("\n")
    title = "Phone call #{inbound ? 'from' : 'to'} #{external}"

    transaction_class.execute(disable: DISPATCH_DISABLE, reset_user_id: true) do
      user       = find_or_create_user(external)
      group      = Group.find_by(id: channel.group_id) || Group.first
      phone_type = Ticket::Article::Type.find_by(name: 'phone')
      closed     = Ticket::State.find_by(name: 'closed')
      sender     = Ticket::Article::Sender.find_by(name: inbound ? 'Customer' : 'Agent')

      if article
        ticket = article.ticket
        stored = (ticket.preferences[prefs_key.to_s] || ticket.preferences[prefs_key.to_sym] || {}).with_indifferent_access
        same   = stored.slice(*prefs.keys.map(&:to_s)) == prefs.with_indifferent_access.slice(*prefs.keys.map(&:to_s)) &&
                 ticket.customer_id == user.id && ticket.title == title
        return :unchanged if same

        ticket.preferences = ticket.preferences.merge(prefs_key.to_s => prefs.deep_stringify_keys)
        ticket.title       = title
        ticket.customer_id = user.id
        ticket.close_at    = start_time + duration
        ticket.updated_by_id = 1
        ticket.save!
        article.update!(body: body, from: external, updated_by_id: 1)
        return :updated
      end

      ticket = Ticket.create!(
        title:                  title,
        group_id:               group.id,
        customer_id:            user.id,
        state_id:               closed&.id || Ticket::State.find_by(default_create: true)&.id,
        priority_id:            Ticket::Priority.find_by(default_create: true)&.id || Ticket::Priority.first&.id,
        create_article_type_id: phone_type&.id,
        preferences:            { prefs_key.to_s => prefs.deep_stringify_keys },
        created_at:             start_time,
        updated_at:             start_time,
        close_at:               start_time + duration,
        created_by_id:          inbound ? user.id : 1,
        updated_by_id:          1,
      )

      Ticket::Article.create!(
        ticket_id:     ticket.id,
        type_id:       phone_type&.id,
        sender_id:     sender&.id,
        from:          external,
        subject:       'Call record',
        body:          body,
        content_type:  'text/plain',
        message_id:    dedup_key,
        internal:      false,
        created_at:    start_time,
        updated_at:    start_time,
        preferences:   { prefs_key.to_s => { 'channel_id' => channel.id } },
        created_by_id: inbound ? user.id : 1,
        updated_by_id: 1,
      )
      :created
    end
  end

  def find_or_create_user(phone)
    user = User.find_by(phone: phone) || User.find_by(mobile: phone)
    return user if user

    User.create!(
      firstname:     phone,
      lastname:      '',
      phone:         phone,
      active:        true,
      role_ids:      Role.signup_role_ids,
      updated_by_id: 1,
      created_by_id: 1,
    )
  end

  # ---- FreePBX side: who answered a call, from the PBX's own records ----

  # Loads the PBX's inbound legs once per job run, covering `since`.
  def pbx_legs(since)
    @pbx_legs ||= begin
      channel = Channel.where(area: 'Freepbx::Account', active: true).order(:id).first
      api_class = 'Kc::FreepbxApi'.safe_constantize
      if channel.nil? || api_class.nil?
        []
      else
        minutes = ((Time.current - since) / 60).ceil + 10
        api_class.for_channel(channel).calls(since_minutes: minutes, direction: 'inbound', limit: 5000)
                 .map(&:with_indifferent_access)
      end
    rescue StandardError => e
      Rails.logger.warn "KC Call History: could not read PBX call legs: #{e.message}"
      []
    end
  end

  def pbx_extension_names
    @pbx_extension_names ||= begin
      channel = Channel.where(area: 'Freepbx::Account', active: true).order(:id).first
      api_class = 'Kc::FreepbxApi'.safe_constantize
      if channel.nil? || api_class.nil?
        {}
      else
        api_class.for_channel(channel).extensions.map(&:with_indifferent_access)
                 .to_h { |e| [e[:extension].to_s, e[:name].to_s] }
      end
    rescue StandardError
      {}
    end
  end

  # The PBX's view of one call: { seen: bool, answered_by: "201", answered_by_name: "Dean" }.
  # Matches on the caller's number within three minutes of the call start,
  # which absorbs the ring time at RingCentral before the forward.
  def pbx_answer_for(caller, start_time, since)
    tail = caller.to_s.delete('^0-9').last(10)
    return { seen: false } if tail.blank?

    legs = pbx_legs(since).select do |leg|
      leg[:src].to_s.delete('^0-9').last(10) == tail &&
        (stamp = Time.zone.parse(leg[:calldate_utc].to_s) rescue nil) &&
        (stamp - start_time).abs <= 180
    end
    return { seen: false } if legs.empty?

    answered = legs.find { |l| l[:disposition].to_s == 'ANSWERED' && l[:billsec].to_i.positive? && l[:dstchannel].to_s =~ %r{PJSIP/(\d+)-} }
    return { seen: true } if answered.nil?

    ext = answered[:dstchannel].to_s[%r{PJSIP/(\d+)-}, 1]
    { seen: true, answered_by: ext, answered_by_name: pbx_extension_names[ext].presence }
  end

  def describe_extension(ext, name)
    name.present? ? "ext #{ext} (#{name})" : "ext #{ext}"
  end

  # ---- text-thread call notes ------------------------------------------

  def thread_notes_enabled?
    Setting.get('kc_ringcentral_sms_call_thread_notes') == true
  end

  # Writes (or refreshes) the call as an internal note on the open SMS
  # ticket for `external`. Returns :noted, :unchanged or nil (no open
  # thread, feature off, or failure). Never raises: a note is a courtesy,
  # the call record must not depend on it.
  #
  # source  'RingCentral' or 'FreePBX' — which system placed or took the call
  # via     optional detail, e.g. "ext 201 (Dean)" for a PBX extension
  def note_call_on_sms_thread(dedup_key:, external:, inbound:, start_time:, duration:, outcome:, line:, source:, via: nil)
    return nil if !thread_notes_enabled?

    external = normalize_number(external)
    return nil if external.blank?

    message_id = "#{THREAD_NOTE_PREFIX}#{dedup_key}"
    note       = Ticket::Article.find_by(message_id: message_id)
    ticket     = note&.ticket || open_sms_thread_for(external)
    return nil if ticket.nil?

    record = Ticket::Article.find_by(message_id: dedup_key)&.ticket
    body   = thread_note_body(inbound:, start_time:, duration:, outcome:, line:, source:, via:, record:)

    transaction_class = 'Transaction'.safe_constantize
    return nil if transaction_class.nil?

    transaction_class.execute(disable: DISPATCH_DISABLE, reset_user_id: true) do
      if note
        next :unchanged if note.body == body

        note.update!(body: body, updated_by_id: 1)
        next :noted
      end
      next :unchanged if noted_by_other_source?(ticket, source, inbound, start_time)

      note = Ticket::Article.create!(
        ticket_id:     ticket.id,
        type_id:       Ticket::Article::Type.find_by(name: 'note')&.id || Ticket::Article::Type.first&.id,
        sender_id:     Ticket::Article::Sender.find_by(name: 'System')&.id || Ticket::Article::Sender.find_by(name: 'Agent')&.id,
        from:          external,
        subject:       'Call activity',
        body:          body,
        content_type:  'text/plain',
        message_id:    message_id,
        internal:      true,
        preferences:   {
          kc_call_note: {
            source:           source,
            direction:        inbound ? 'inbound' : 'outbound',
            outcome:          outcome,
            start_time:       start_time.utc.iso8601,
            duration:         duration,
            record_ticket_id: record&.id,
          },
        },
        created_by_id: 1,
        updated_by_id: 1,
      )
      # Sort the note where the call happened in the conversation, not
      # where the poll caught up with it.
      note.update_columns(created_at: start_time, updated_at: start_time) # rubocop:disable Rails/SkipsModelValidations
      Rails.logger.info "KC Call History: noted #{source} call #{dedup_key} on SMS ticket #{ticket.id}"
      :noted
    end
  rescue StandardError => e
    Rails.logger.warn "KC Call History: could not note call #{dedup_key} on the SMS thread: #{e.message}"
    nil
  end

  def thread_note_body(inbound:, start_time:, duration:, outcome:, line:, source:, via:, record:)
    origin = via.present? ? "#{source} (#{via})" : source
    lines  = [
      "#{inbound ? 'Inbound' : 'Outbound'} call via #{origin} — #{outcome}",
      line,
      "Time: #{start_time.in_time_zone.strftime('%Y-%m-%d %H:%M')}  Duration: #{format('%d:%02d', duration / 60, duration % 60)}",
    ]
    lines << "Call record: #{Setting.get('ticket_hook')}#{record.number}" if record
    lines.compact.join("\n")
  end

  # The most recently active SMS ticket for `number` that is not closed:
  # any ticket the SMS integration can reply from (an SMS conversation, an
  # agent-started text, a missed-call ticket with SMS reply enabled) whose
  # customer side is this number. Pending states count as open; anything
  # closed, merged, removed or in a KC locked-closed state does not.
  def open_sms_thread_for(number)
    number = normalize_number(number)
    return nil if number.blank?

    closed_state_ids = Ticket::State
                         .joins(:state_type)
                         .where("ticket_state_types.name IN (?) OR ticket_states.name LIKE 'closed%'", %w[closed merged removed])
                         .pluck(:id)

    # preferences is YAML; the number is quoted there, so match it whole.
    Ticket.where('preferences LIKE ?', '%ringcentral_sms:%')
          .where('preferences LIKE ?', "%\"#{ActiveRecord::Base.sanitize_sql_like(number)}\"%")
          .where.not(state_id: closed_state_ids)
          .order(updated_at: :desc)
          .limit(25)
          .detect { |ticket| sms_thread_numbers(ticket).include?(number) }
  end

  def sms_thread_numbers(ticket)
    prefs = ticket.preferences || {}
    sms   = (prefs['ringcentral_sms'] || prefs[:ringcentral_sms] || {}).with_indifferent_access
    return [] if sms.blank?

    ([sms[:from_phone]] + Array(sms[:participants]) + Array(sms[:to_phones]))
      .filter_map { |n| normalize_number(n) }
      .reject { |n| own_number?(n) }
  end

  # One call can be seen from both systems: RingCentral forwards to the PBX
  # and may trunk its calls. A note from the other system for the same
  # direction within three minutes is that call, and stays the one note.
  # Same-source calls are told apart by their own dedup keys.
  def noted_by_other_source?(ticket, source, inbound, start_time)
    direction = inbound ? 'inbound' : 'outbound'
    Ticket::Article
      .where(ticket_id: ticket.id, created_at: (start_time - 3.minutes)..(start_time + 3.minutes))
      .where('message_id LIKE ?', "#{THREAD_NOTE_PREFIX}%")
      .any? do |other|
        info = ((other.preferences || {}).with_indifferent_access[:kc_call_note] || {}).with_indifferent_access
        info[:source].to_s != source && info[:direction].to_s == direction
      end
  end
end
