# KC: Two-way contact sync between Zammad and one RingCentral SMS channel's
# personal address book.
#
# Import (channel option contact_import):
#   Every address-book contact that has a name and at least one number or
#   email becomes a Zammad customer, or is matched to an existing user:
#     1. the user this contact was matched to on an earlier run
#        (preferences[:kc_ringcentral_contacts][<channel id>][:contact_id])
#     2. a user with the contact's email
#     3. a user whose phone or mobile is one of the contact's numbers
#        (last-ten-digit match, active users only). Several different named
#        users on the contact's numbers is ambiguous and the contact is
#        skipped.
#   A placeholder user (named after their own number, see
#   Kc::PhoneContacts.placeholder?) gets the contact's name. Any other user
#   only has blank fields filled: a name or email set by a person or the
#   directory sync is never overwritten. A new customer is created when
#   nothing matches. An existing organization whose name equals the
#   contact's company exactly is linked to a user without one; organizations
#   are never created.
#
# Export (channel option contact_export):
#   Every active user from the Microsoft 365 directory sync (has a
#   microsoft_teams authorization, any tenant) with a phone or mobile gets a
#   contact in the address book: firstName/lastName, company = organization,
#   email, mobile -> mobilePhone, phone -> businessPhone, and EXPORT_MARKER in
#   notes. The contact id is kept in the user's preferences and the contact
#   is updated when the name, numbers, email or organization change.
#   A contact staff created by hand that already carries one of the user's
#   numbers is never changed or duplicated: the match is only recorded.
#   A synced contact whose marker staff removed is treated the same way from
#   then on. A synced contact staff deleted in RingCentral is not created
#   again. Nothing is ever deleted in RingCentral: contacts of users who are
#   deactivated later stay in the address book as they are.
#
# Loop prevention: import skips every contact carrying EXPORT_MARKER or
# recorded as exported, so exported directory users never come back as
# imported contacts.
#
# Rate limits: RingCentral puts address-book writes in its "Heavy" group
# (10 requests a minute). Writes are spaced WRITE_INTERVAL apart and capped
# at MAX_WRITES per run; a 429 waits for Retry-After once (up to
# MAX_RETRY_WAIT) and otherwise stops the export. Progress is kept per
# user, so the next run carries on where this one stopped.
class Kc::RingcentralContactSync
  CHANNEL_AREA   = 'RingCentralSms::Account'.freeze
  PREFERENCE_KEY = 'kc_ringcentral_contacts'.freeze
  EXPORT_MARKER  = 'Synced from Zammad directory'.freeze
  EXPORT_NOTE    = "#{EXPORT_MARKER}. Remove this line to stop Zammad updating this contact.".freeze

  MAX_PAGES      = 20
  PAGE_SIZE      = 250
  WRITE_INTERVAL = 6.5 # seconds; 10 heavy requests a minute
  MAX_WRITES     = 150
  MAX_RETRY_WAIT = 60

  PHONE_FIELDS = %w[
    mobilePhone businessPhone businessPhone2 homePhone homePhone2 companyPhone
    carPhone otherPhone callbackPhone assistantPhone
  ].freeze

  # Fields of a contact the export owns; everything else staff put on the
  # contact is kept when it is updated.
  EXPORT_FIELDS = %w[firstName lastName company email mobilePhone businessPhone].freeze
  READ_ONLY_FIELDS = %w[id uri availability].freeze

  # Stops the export for this run (rate limit, write cap, permission).
  class StopExport < StandardError; end

  attr_reader :channel, :stats

  def initialize(channel)
    @channel = channel
    @stats = {
      import: { created: 0, updated: 0, unchanged: 0, skipped: 0, errors: 0 },
      export: { created: 0, updated: 0, unchanged: 0, skipped: 0, errors: 0 },
    }
    @errors = []
    @writes = 0
    @last_write_at = nil
  end

  def import_enabled?
    ActiveModel::Type::Boolean.new.cast(options[:contact_import]) == true
  end

  def export_enabled?
    ActiveModel::Type::Boolean.new.cast(options[:contact_export]) == true
  end

  # Runs import and/or export as enabled and returns the result hash that
  # is also stored on the channel as options[:last_contact_sync].
  def run
    started_at = Time.current
    status     = 'completed'

    if import_enabled? || export_enabled?
      contacts = fetch_contacts
      if contacts
        import_contacts(contacts) if import_enabled?
        export_users(contacts)    if export_enabled?
      else
        status = 'failed'
      end
    else
      status = 'disabled'
    end

    status = 'completed_with_errors' if status == 'completed' && @errors.any?
    result = {
      status:      status,
      started_at:  started_at.iso8601,
      finished_at: Time.current.iso8601,
      import:      import_enabled? ? stats[:import] : nil,
      export:      export_enabled? ? stats[:export] : nil,
      last_error:  @errors.last,
      error_count: @errors.size,
    }
    store_result(result)
    result
  end

  private

  def options
    (channel.options || {}).with_indifferent_access
  end

  def rc_class
    @rc_class ||= 'Kc::RingcentralApi'.safe_constantize
  end

  def client
    @client ||= rc_class.with_channel_tokens(channel)
  end

  # On a 401 the token is refreshed once and the call repeated.
  def with_client
    yield client
  rescue rc_class::AuthError
    @client = rc_class.with_channel_tokens(channel, force_refresh: true)
    yield @client
  end

  # ------------------------------------------------------------------
  # Address book
  # ------------------------------------------------------------------

  # All contacts, or nil when the book could not be read.
  def fetch_contacts
    raise 'RingCentral API client not available' if rc_class.nil?

    contacts = []
    (1..MAX_PAGES).each do |page|
      result  = with_client { |rc| rc.address_book_contacts(page: page, per_page: PAGE_SIZE) }
      records = Array(result['records'] || result[:records]).map { |record| record.to_h.stringify_keys }
      contacts.concat(records)
      total = (result['paging'] || result[:paging] || {}).with_indifferent_access[:totalPages].to_i
      break if records.empty? || page >= total
    end
    contacts
  rescue => e
    record_error("Could not read the RingCentral address book: #{describe_error(e)}")
    nil
  end

  def exported_contact?(contact)
    contact['notes'].to_s.include?(EXPORT_MARKER) ||
      exported_contact_ids.include?(contact['id'].to_s)
  end

  def contact_name(contact)
    [contact['firstName'], contact['lastName']].map { |part| part.to_s.strip }.compact_blank.join(' ').presence
  end

  def contact_keys(contact)
    PHONE_FIELDS.filter_map { |field| match_key(contact[field]) }.uniq
  end

  def match_key(number)
    Kc::PhoneContacts.match_key(number)
  end

  def normalize(number)
    return nil if match_key(number).nil?

    Kc::PhoneContacts.normalize(number)
  end

  def placeholder?(user)
    Kc::PhoneContacts.placeholder?(user)
  end

  # ------------------------------------------------------------------
  # Sync state on users
  # ------------------------------------------------------------------

  def channel_key
    channel.id.to_s
  end

  def sync_state(user)
    all = user.preferences[PREFERENCE_KEY] || user.preferences[PREFERENCE_KEY.to_sym] || {}
    (all[channel_key] || all[channel.id] || {}).to_h.stringify_keys
  end

  def save_sync_state(user, state)
    all = (user.preferences[PREFERENCE_KEY] || user.preferences[PREFERENCE_KEY.to_sym] || {}).to_h.deep_stringify_keys
    if state.nil?
      all.delete(channel_key)
    else
      all[channel_key] = state.merge('synced_at' => Time.current.iso8601)
    end
    user.preferences[PREFERENCE_KEY] = all
    user.updated_by_id = 1
    user.save!
  end

  # Users that hold sync state for this channel, by contact id.
  def users_by_contact_id
    @users_by_contact_id ||= begin
      index = {}
      User.where('preferences LIKE ?', "%#{PREFERENCE_KEY}%").find_each do |user|
        state = sync_state(user)
        index[state['contact_id'].to_s] = user if state['contact_id'].present?
      end
      index
    end
  end

  def exported_contact_ids
    @exported_contact_ids ||= users_by_contact_id.select { |_, user| sync_state(user)['origin'] == 'export' }.keys.to_set
  end

  # ------------------------------------------------------------------
  # Import
  # ------------------------------------------------------------------

  def import_contacts(contacts)
    contacts.each do |contact|
      import_contact(contact)
    rescue => e
      stats[:import][:errors] += 1
      record_error("Import of RingCentral contact #{contact['id']} failed: #{e.message}")
    end
  end

  def import_contact(contact)
    name   = contact_name(contact)
    email  = usable_email(contact['email'])
    keys   = contact_keys(contact)

    if exported_contact?(contact) || name.blank? || (email.blank? && keys.empty?)
      stats[:import][:skipped] += 1
      return
    end

    user = find_import_user(contact, email, keys)
    if user == :ambiguous
      stats[:import][:skipped] += 1
      return
    end

    if user
      changed = update_imported_user(user, contact, email)
      remember_import(user, contact)
      stats[:import][changed ? :updated : :unchanged] += 1
    else
      user = create_imported_user(contact, email)
      users_by_contact_id[contact['id'].to_s] = user
      stats[:import][:created] += 1
    end
  end

  def find_import_user(contact, email, keys)
    known = users_by_contact_id[contact['id'].to_s]
    return known if known && sync_state(known)['origin'] != 'export'

    if email
      by_email = User.find_by(email: email)
      return by_email if by_email
    end

    users_for_keys(keys)
  end

  # The one user owning the numbers, :ambiguous, or nil. Named users win
  # over placeholders; with only placeholders the oldest one is upgraded.
  def users_for_keys(keys)
    return nil if keys.empty?

    candidates = keys.flat_map { |key| users_with_key(key) }.uniq
    named = candidates.reject { |user| placeholder?(user) }
    return named.first if named.size == 1
    return :ambiguous if named.size > 1

    candidates.min_by(&:id)
  end

  def users_with_key(key)
    if ActiveRecord::Base.connection.adapter_name.match?(%r{postg}i)
      User.where(active: true)
          .where("right(regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g'), 10) = :key OR " \
                 "right(regexp_replace(coalesce(mobile, ''), '[^0-9]', '', 'g'), 10) = :key", key: key)
          .limit(10).to_a
    else
      User.where(active: true).where('phone LIKE :key OR mobile LIKE :key', key: "%#{key}").limit(10).to_a
    end
  end

  def update_imported_user(user, contact, email)
    attrs = {}
    first = contact['firstName'].to_s.strip
    last  = contact['lastName'].to_s.strip

    if placeholder?(user)
      first, last = split_name(contact_name(contact)) if first.blank?
      attrs[:firstname] = first
      attrs[:lastname]  = last
    elsif user.firstname.to_s.strip.blank? && user.lastname.to_s.strip.blank?
      attrs[:firstname] = first.presence || last
      attrs[:lastname]  = first.present? ? last : ''
    end

    attrs[:email] = email if email && user.email.blank? && !email_taken?(email, user)

    user_keys = [match_key(user.phone), match_key(user.mobile)].compact
    mobile = normalize(contact['mobilePhone'])
    if mobile && user.mobile.blank? && user_keys.exclude?(match_key(mobile))
      attrs[:mobile] = mobile
      user_keys << match_key(mobile)
    end
    phone = other_number(contact, user_keys)
    attrs[:phone] = phone if phone && user.phone.blank?

    org = matching_organization(contact)
    attrs[:organization_id] = org.id if org && user.organization_id.blank?

    attrs.reject! { |key, value| user.send(key).to_s == value.to_s }
    return false if attrs.empty?

    user.update!(attrs.merge(updated_by_id: 1))
    true
  end

  def create_imported_user(contact, email)
    first = contact['firstName'].to_s.strip
    last  = contact['lastName'].to_s.strip
    first, last = [last, ''] if first.blank?
    mobile = normalize(contact['mobilePhone'])
    phone  = other_number(contact, [match_key(mobile)].compact)
    org    = matching_organization(contact)

    User.create!(
      firstname:       first,
      lastname:        last,
      email:           email && !email_taken?(email, nil) ? email : nil,
      mobile:          mobile,
      phone:           phone,
      organization_id: org&.id,
      active:          true,
      role_ids:        Role.signup_role_ids,
      preferences:     { PREFERENCE_KEY => { channel_key => import_state(contact) } },
      updated_by_id:   1,
      created_by_id:   1,
    )
  end

  def remember_import(user, contact)
    state = sync_state(user)
    return if state['contact_id'].to_s == contact['id'].to_s && state['origin'] == 'import'
    # A user exported to this channel keeps its export record.
    return if state['origin'] == 'export'

    save_sync_state(user, import_state(contact))
  end

  def import_state(contact)
    { 'contact_id' => contact['id'].to_s, 'origin' => 'import', 'synced_at' => Time.current.iso8601 }
  end

  # The contact's first number other than the mobile, normalized.
  def other_number(contact, exclude_keys)
    (PHONE_FIELDS - ['mobilePhone']).each do |field|
      key = match_key(contact[field])
      next if key.nil? || exclude_keys.include?(key)

      return normalize(contact[field])
    end
    nil
  end

  def matching_organization(contact)
    company = contact['company'].to_s.strip
    return nil if company.blank?

    Organization.find_by(name: company)
  end

  def usable_email(value)
    email = value.to_s.strip.downcase
    return nil if email.blank?

    validator = 'EmailAddressValidation'.safe_constantize
    return email if validator.nil?

    validator.new(email).valid? ? email : nil
  end

  def email_taken?(email, user)
    scope = User.where(email: email)
    scope = scope.where.not(id: user.id) if user
    scope.exists?
  end

  def split_name(name)
    parts = name.to_s.strip.split(%r{\s+}, 2)
    [parts[0].to_s, parts[1].to_s]
  end

  # ------------------------------------------------------------------
  # Export
  # ------------------------------------------------------------------

  def export_users(contacts)
    book_by_id  = contacts.index_by { |contact| contact['id'].to_s }
    book_by_key = {}
    contacts.each do |contact|
      contact_keys(contact).each { |key| (book_by_key[key] ||= []) << contact }
    end
    claimed = exported_contact_ids.to_set

    directory_users.each do |user|
      export_user(user, book_by_id, book_by_key, claimed)
    rescue StopExport
      break
    rescue => e
      stats[:export][:errors] += 1
      record_error("Export of user #{user.id} failed: #{describe_error(e)}")
    end
  end

  def directory_users
    User.where(active: true)
        .where(id: Authorization.where(provider: 'microsoft_teams').select(:user_id))
        .where("coalesce(phone, '') <> '' OR coalesce(mobile, '') <> ''")
        .reorder(:id)
  end

  def export_user(user, book_by_id, book_by_key, claimed)
    payload = export_payload(user)
    keys    = [match_key(payload['mobilePhone']), match_key(payload['businessPhone'])].compact.uniq
    if keys.empty?
      stats[:export][:skipped] += 1
      return
    end

    state   = sync_state(user)
    current = state['contact_id'].present? ? book_by_id[state['contact_id'].to_s] : nil

    case state['origin']
    when 'export'
      return export_update(user, state, current, payload) if current && current['notes'].to_s.include?(EXPORT_MARKER)

      # Staff removed the marker (now theirs) or deleted the contact.
      save_sync_state(user, state.merge('origin' => current ? 'manual' : 'deleted'))
      stats[:export][:skipped] += 1
      return
    when 'deleted'
      stats[:export][:skipped] += 1
      return
    when 'manual', 'import'
      if current && keys.intersect?(contact_keys(current))
        stats[:export][:skipped] += 1
        return
      end
    end

    existing = keys.flat_map { |key| book_by_key[key] || [] }.uniq { |contact| contact['id'].to_s }
    ours     = existing.find { |contact| contact['notes'].to_s.include?(EXPORT_MARKER) && claimed.exclude?(contact['id'].to_s) }
    if ours
      # Ours, but its record on the user was lost: adopt it.
      claimed << ours['id'].to_s
      return export_update(user, { 'contact_id' => ours['id'].to_s, 'origin' => 'export' }, ours, payload)
    end

    if existing.any?
      manual = existing.find { |contact| contact['notes'].to_s.exclude?(EXPORT_MARKER) }
      if manual
        save_sync_state(user, { 'contact_id' => manual['id'].to_s, 'origin' => 'manual' }) if state['contact_id'].to_s != manual['id'].to_s
      elsif state.present?
        save_sync_state(user, nil)
      end
      # Same number as another directory user's synced contact, or a
      # contact staff made: nothing to write.
      stats[:export][:skipped] += 1
      return
    end

    created = write { |rc| rc.create_address_book_contact(payload.merge('notes' => EXPORT_NOTE)) }
    created = created.to_h.stringify_keys
    raise 'RingCentral returned no contact id' if created['id'].blank?

    claimed << created['id'].to_s
    keys.each { |key| (book_by_key[key] ||= []) << created }
    book_by_id[created['id'].to_s] = created
    save_sync_state(user, { 'contact_id' => created['id'].to_s, 'origin' => 'export', 'fingerprint' => fingerprint(payload) })
    stats[:export][:created] += 1
  end

  def export_update(user, state, current, payload)
    print = fingerprint(payload)
    if state['fingerprint'] == print && same_as_contact?(current, payload)
      stats[:export][:unchanged] += 1
      return
    end

    if same_as_contact?(current, payload)
      save_sync_state(user, state.merge('origin' => 'export', 'fingerprint' => print))
      stats[:export][:unchanged] += 1
      return
    end

    body = current.except(*READ_ONLY_FIELDS).merge(payload)
    EXPORT_FIELDS.each { |field| body.delete(field) if body[field].blank? }
    write { |rc| rc.update_address_book_contact(state['contact_id'], body) }
    save_sync_state(user, state.merge('origin' => 'export', 'fingerprint' => print))
    stats[:export][:updated] += 1
  end

  def same_as_contact?(contact, payload)
    EXPORT_FIELDS.all? do |field|
      ours   = payload[field].to_s
      theirs = contact[field].to_s
      if field.end_with?('Phone')
        match_key(ours) == match_key(theirs)
      else
        ours.strip.casecmp?(theirs.strip)
      end
    end
  end

  def export_payload(user)
    email = user.email.to_s.strip
    email = '' if email.end_with?('@teams.local')
    mobile = normalize(user.mobile)
    phone  = normalize(user.phone)
    phone  = nil if phone && match_key(phone) == match_key(mobile)
    first  = user.firstname.to_s.strip
    last   = user.lastname.to_s.strip

    {
      'firstName'     => first.presence,
      'lastName'      => last.presence,
      'company'       => user.organization&.name.to_s.strip.presence,
      'email'         => email.presence,
      'mobilePhone'   => mobile,
      'businessPhone' => phone,
    }.compact
  end

  def fingerprint(payload)
    Digest::SHA256.hexdigest(payload.sort.to_h.to_json)
  end

  # One address-book write, spaced and capped for the rate limit.
  def write
    raise StopExport if stop_for_cap?

    throttle
    attempts = 0
    begin
      attempts += 1
      @writes += 1
      @last_write_at = monotonic_now
      with_client { |rc| yield rc }
    rescue rc_class::RateLimitError => e
      wait = e.retry_after || MAX_RETRY_WAIT
      if attempts == 1 && wait <= MAX_RETRY_WAIT
        pause(wait)
        retry
      end
      record_error("RingCentral rate limit reached; the remaining contacts are synced on the next run (#{e.message}).")
      raise StopExport
    rescue rc_class::AuthError => e
      record_error("RingCentral rejected the access token; reauthenticate the account. #{e.message}")
      raise StopExport
    rescue rc_class::PermissionError => e
      record_error('RingCentral refused to change the address book (permission denied). ' \
                   "Give the RingCentral app the Contacts permission and reauthenticate the account. #{e.message}")
      raise StopExport
    end
  end

  def stop_for_cap?
    return false if @writes < MAX_WRITES

    record_error("Stopped after #{MAX_WRITES} address-book changes; the rest follow on the next run.") if !@cap_noted
    @cap_noted = true
    true
  end

  def throttle
    return if @last_write_at.nil?

    wait = WRITE_INTERVAL - (monotonic_now - @last_write_at)
    pause(wait) if wait.positive?
  end

  def pause(seconds)
    sleep(seconds)
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # ------------------------------------------------------------------
  # Result
  # ------------------------------------------------------------------

  def describe_error(error)
    return "permission denied (#{error.message})" if rc_class && error.is_a?(rc_class::PermissionError)

    error.message
  end

  def record_error(message)
    @errors << message.to_s.truncate(500)
    Rails.logger.warn "KC RingCentral Contact Sync: channel #{channel.id}: #{message}"
  end

  def store_result(result)
    channel.with_lock do
      channel.reload
      channel.options[:last_contact_sync] = result.deep_stringify_keys
      channel.save!
    end
  rescue => e
    Rails.logger.error "KC RingCentral Contact Sync: could not store the result on channel #{channel.id}: #{e.message}"
  end
end
