# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Kc::SmsTicketBlocklist
  SETTING_NAME = 'kc_sms_ticket_blocked_numbers'.freeze

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

  def self.validate!(value)
    entries(value).each do |entry|
      raise ArgumentError, 'Enter valid phone numbers, one per line. Use +country code for international numbers.' if normalize(entry).nil?
    end
  end

  def self.blocked?(*numbers)
    blocked = entries(Setting.get(SETTING_NAME)).filter_map { |entry| normalize(entry) }
    numbers.flatten.filter_map { |number| normalize(number) }.intersect?(blocked)
  end

  def self.blocked_message?(message)
    blocked?(message[:from_phone], message[:to_phone], message[:to_phones])
  end

  def self.ensure_setting!
    Setting.create_if_not_exists(
      title:       'SMS ticket blocked numbers',
      name:        SETTING_NAME,
      area:        'Kc::RingCentralSms',
      description: 'Skip ticket imports for SMS conversations containing these numbers, including incoming messages, external outbound captures, and backfills. Messages remain in RingCentral or FreePBX. Existing tickets and voice calls are unchanged. Empty means no blocked numbers.',
      options:     { form: [{ display: 'Blocked numbers', null: true, name: SETTING_NAME, tag: 'textarea' }] },
      state:       '',
      preferences: { permission: ['admin'], validations: ['Setting::Validation::KcSmsTicketBlocklist'] },
      frontend:    true,
    )
  end
end
