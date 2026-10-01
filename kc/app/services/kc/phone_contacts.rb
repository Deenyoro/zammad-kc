# KC: Names for phone numbers, so SMS tickets and call notes show who is
# texting or calling instead of a bare number.
#
# Lookup order for a number:
#   1. A Zammad user whose phone or mobile is that number. This includes the
#      people the Microsoft 365 directory sync imported (their mobile comes
#      from Entra ID). Users the SMS and call integrations created as
#      placeholders, named after the number itself, do not count.
#   2. The RingCentral address book of every active RingCentral channel.
#   3. The FreePBX phonebook, through the connector's optional /contacts.
#
# The RingCentral and FreePBX books are read whole and cached for
# BOOK_TTL, so a busy SMS day costs one request per book per half hour.
# A source that fails or does not exist is cached as empty for
# FAILED_TTL; a name is a nicety and never blocks a message.
#
# Numbers are compared on their last ten digits (the national number for
# North America), so "+1 (412) 555-0100", "4125550100" and "+14125550100"
# are the same contact.
class Kc::PhoneContacts
  RC_AREA  = 'RingCentralSms::Account'.freeze
  PBX_AREA = 'Freepbx::Account'.freeze

  BOOK_TTL   = 30.minutes
  FAILED_TTL = 10.minutes
  RC_MAX_PAGES = 20

  RC_PHONE_FIELDS = %w[
    mobilePhone businessPhone businessPhone2 homePhone homePhone2 companyPhone
    carPhone otherPhone callbackPhone assistantPhone
  ].freeze

  class << self
    # "Jane Smith" or nil.
    def name_for(number)
      key = match_key(number)
      return nil if key.blank?

      user = find_user(number)
      name = user && !placeholder?(user) && user_name(user)
      return name if name.present?

      book_name_for(number)
    rescue => e
      Rails.logger.warn "KC PhoneContacts: lookup failed for a number: #{e.message}"
      nil
    end

    # The RingCentral or FreePBX contact name for a number, or nil.
    def book_name_for(number)
      key = match_key(number)
      return nil if key.blank?

      ringcentral_book[key].presence || freepbx_book[key].presence
    end

    # "Jane Smith (+14125550100)", or the number alone when nobody matches.
    def display(number, name: :lookup)
      normalized = normalize(number) || number.to_s
      name = name_for(normalized) if name == :lookup
      name.present? ? "#{name} (#{normalized})" : normalized
    end

    # The customer behind a number: an exact phone/mobile match first (what
    # the integrations always did), then a single user whose number is
    # stored in another format. Several different users on one number is
    # ambiguous and matches nobody.
    def find_user(number)
      normalized = normalize(number)
      return nil if normalized.blank?

      exact = User.find_by(phone: normalized) || User.find_by(mobile: normalized)
      return exact if exact && !placeholder?(exact)

      loose = loose_user_matches(normalized)
      return loose.first if loose.size == 1

      exact
    end

    # find_user, or a new customer for the number. A new customer, and an
    # existing placeholder, are named after the contact when one is known.
    def find_or_create_customer(number)
      normalized = normalize(number)
      user = find_user(normalized)
      if user
        enrich_placeholder(user, normalized)
        return user
      end

      first, last = split_name(name_for(normalized))
      User.create!(
        firstname:     first.presence || normalized,
        lastname:      last.to_s,
        phone:         normalized,
        active:        true,
        role_ids:      Role.signup_role_ids,
        updated_by_id: 1,
        created_by_id: 1,
      )
    end

    # Renames a placeholder customer ("+14125550100") after the contact.
    # Returns true when the user was renamed.
    def enrich_placeholder(user, number = nil)
      return false if user.nil? || !placeholder?(user)

      name = book_name_for(number || user.phone.presence || user.mobile)
      return false if name.blank?

      first, last = split_name(name)
      user.update!(firstname: first, lastname: last.to_s, updated_by_id: 1)
      true
    rescue => e
      Rails.logger.warn "KC PhoneContacts: could not name user #{user&.id}: #{e.message}"
      false
    end

    # A user the integrations created for an unknown number: named after
    # the number, nothing else.
    def placeholder?(user)
      first = user.firstname.to_s.strip
      return false if user.lastname.to_s.strip.present?
      return true if first.blank? && user.email.blank?

      first.match?(%r{\A\+?[\d\s().-]{7,}\z})
    end

    def user_name(user)
      name = [user.firstname, user.lastname].map { |part| part.to_s.strip }.compact_blank.join(' ')
      name.presence
    end

    # Last ten digits (all digits for shorter international numbers).
    def match_key(number)
      digits = number.to_s.delete('^0-9')
      return nil if digits.length < 7

      digits.length > 10 ? digits.last(10) : digits
    end

    def normalize(number)
      return nil if number.blank?

      rc = 'Kc::RingcentralApi'.safe_constantize
      rc ? rc.normalize_phone(number) : number.to_s
    end

    def ringcentral_book
      cached_book('kc_phone_contacts:ringcentral') { load_ringcentral_book }
    end

    def freepbx_book
      cached_book('kc_phone_contacts:freepbx') { load_freepbx_book }
    end

    # Loads both books into the cache. Callers do this before they open a
    # database transaction, so the HTTP requests and the RingCentral token
    # lock are not held inside it.
    def warm!
      ringcentral_book
      freepbx_book
      true
    rescue
      false
    end

    def reset_cache!
      Rails.cache.delete('kc_phone_contacts:ringcentral')
      Rails.cache.delete('kc_phone_contacts:freepbx')
    end

    private

    def loose_user_matches(normalized)
      key = match_key(normalized)
      return [] if key.blank?
      return [] if !ActiveRecord::Base.connection.adapter_name.match?(%r{postg}i)

      User.where(active: true)
          .where("right(regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g'), 10) = :key OR " \
                 "right(regexp_replace(coalesce(mobile, ''), '[^0-9]', '', 'g'), 10) = :key", key: key)
          .limit(10)
          .reject { |user| placeholder?(user) }
    end

    def split_name(name)
      parts = name.to_s.strip.split(%r{\s+}, 2)
      [parts[0].to_s, parts[1].to_s]
    end

    def cached_book(cache_key)
      cached = Rails.cache.read(cache_key)
      return cached if cached.is_a?(Hash)

      book, ok = yield
      Rails.cache.write(cache_key, book, expires_in: ok ? BOOK_TTL : FAILED_TTL)
      book
    end

    # [book, ok]
    def load_ringcentral_book
      rc_class = 'Kc::RingcentralApi'.safe_constantize
      return [{}, true] if rc_class.nil?

      book = {}
      ok   = true
      Channel.where(area: RC_AREA, active: true).reorder(:id).each do |channel|
        rc = rc_class.with_channel_tokens(channel)
        (1..RC_MAX_PAGES).each do |page|
          result  = rc.address_book_contacts(page: page)
          records = Array(result['records'] || result[:records])
          records.each { |contact| add_ringcentral_contact(book, contact.with_indifferent_access) }
          total = (result['paging'] || result[:paging] || {}).with_indifferent_access[:totalPages].to_i
          break if records.empty? || page >= total
        end
      rescue => e
        ok = false
        Rails.logger.warn "KC PhoneContacts: RingCentral address book unavailable for channel #{channel.id}: #{e.message}"
      end
      [book, ok]
    end

    def add_ringcentral_contact(book, contact)
      name = [contact[:firstName], contact[:lastName]].map { |part| part.to_s.strip }.compact_blank.join(' ').presence ||
             contact[:company].to_s.strip.presence
      return if name.blank?

      RC_PHONE_FIELDS.each do |field|
        key = match_key(contact[field])
        book[key] ||= name if key
      end
    end

    def load_freepbx_book
      api_class = 'Kc::FreepbxApi'.safe_constantize
      return [{}, true] if api_class.nil?

      book = {}
      ok   = true
      Channel.where(area: PBX_AREA, active: true).reorder(:id).each do |channel|
        api_class.for_channel(channel).contacts.each do |contact|
          contact = contact.with_indifferent_access
          name    = contact[:name].to_s.strip
          next if name.blank?

          Array(contact[:numbers]).each do |number|
            key = match_key(number)
            book[key] ||= name if key
          end
        end
      rescue => e
        # A connector without the endpoint answers 404; that is not an outage.
        next if e.message.include?('(404)')

        ok = false
        Rails.logger.warn "KC PhoneContacts: FreePBX phonebook unavailable for channel #{channel.id}: #{e.message}"
      end
      [book, ok]
    end
  end
end
