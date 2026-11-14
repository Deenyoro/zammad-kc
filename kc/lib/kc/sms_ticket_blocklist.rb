# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Kc::SmsTicketBlocklist
  SETTING_NAME = 'kc_sms_ticket_blocked_numbers'.freeze
  # Narrow permission for editing only this list. Administrators have it through
  # `admin`; an API token can be given just this one (for example kc-ops) without
  # full admin rights.
  PERMISSION_NAME = 'admin.kc_sms_blocklist'.freeze
  DESCRIPTION = 'Skip ticket imports for SMS conversations containing these numbers, including incoming messages, external outbound captures, and backfills. One entry per line. To block only a group chat, join its numbers with & (for example +14125550100 & +14125550101): conversations with all of them together are skipped, one-to-one texts with them still create tickets. Messages remain in RingCentral or FreePBX. Existing tickets and voice calls are unchanged. Empty means no blocked numbers.'.freeze

  def self.entries(value)
    return [] if value.nil?
    raise ArgumentError, 'Enter phone numbers as text, one per line.' if !value.is_a?(String) || !value.valid_encoding?

    value.split(/[\r\n,;]+/).map(&:strip).reject(&:empty?)
  end

  def self.normalize(value)
    text = value.to_s
    return if !text.valid_encoding?

    text = text.strip
    return if !text.match?(/\A\+?[0-9(). -]+\z/)

    digits = text.gsub(/\D/, '')
    return if !(3..15).cover?(digits.length)

    digits = "1#{digits}" if digits.length == 10 && !text.start_with?('+')
    "+#{digits}"
  end

  GROUP_SEPARATOR = '&'.freeze

  # One rule per entry: a single number blocks every conversation it takes part
  # in; a group entry ("+1 412 555 0100 & +1 412 555 0101") blocks only
  # conversations in which all of its numbers take part together, so one-to-one
  # texts with those people still create tickets.
  def self.rule(entry)
    parts = entry.split(GROUP_SEPARATOR, -1).map(&:strip)
    numbers = parts.map { |part| normalize(part) }
    return if numbers.any?(&:nil?)
    return if parts.length > 1 && numbers.uniq.length < 2

    numbers.uniq
  end

  def self.rules(value)
    entries(value).filter_map { |entry| rule(entry) }
  end

  def self.validate!(value)
    entries(value).each do |entry|
      next if rule(entry)

      raise ArgumentError, 'Enter valid phone numbers, one per line. Use +country code for international numbers. ' \
                           'For a group chat, join two or more numbers with &.'
    end
  end

  def self.blocked?(*numbers)
    participants = numbers.flatten.filter_map { |number| normalize(number) }
    return false if participants.empty?

    rules(Setting.get(SETTING_NAME)).any? { |numbers_of_rule| (numbers_of_rule - participants).empty? }
  end

  def self.blocked_message?(message)
    blocked?(message[:from_phone], message[:to_phone], message[:to_phones])
  end

  def self.ensure_setting!
    Setting.create_if_not_exists(
      title:       'SMS ticket blocked numbers',
      name:        SETTING_NAME,
      area:        'Kc::RingCentralSms',
      description: DESCRIPTION,
      options:     { form: [{ display: 'Blocked numbers', null: true, name: SETTING_NAME, tag: 'textarea' }] },
      state:       '',
      preferences: { permission: [PERMISSION_NAME], validations: ['Setting::Validation::KcSmsTicketBlocklist'] },
      frontend:    true,
    )
  end

  def self.ensure_permission!
    Permission.create_if_not_exists(
      name:        PERMISSION_NAME,
      label:       'SMS ticket blocklist',
      description: 'Manage the SMS numbers that never create tickets.',
      preferences: { prio: 1221 },
    )
  end

  # Existing databases: create the permission and move the setting onto it.
  def self.ensure_access!
    ensure_permission!
    ensure_setting!
    setting = Setting.find_by(name: SETTING_NAME)
    return if setting.nil?
    return if setting.preferences[:permission] == [PERMISSION_NAME] && setting.description == DESCRIPTION

    setting.preferences[:permission] = [PERMISSION_NAME]
    setting.description = DESCRIPTION
    setting.save!
  end
end
