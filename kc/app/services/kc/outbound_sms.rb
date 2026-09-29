# KC: One place to send an SMS from any number configured in the system.
#
# Every outbound SMS the system itself sends — a RingCentral missed-call
# reply, a FreePBX missed-call reply, anything added later — goes through
# here. The caller says which number it wants to text *from*; this service
# finds the channel that owns that number and sends through it. RingCentral
# numbers send through RingCentral; when FreePBX texting is enabled
# (kc_freepbx_sms_enabled), the PBX's texting numbers are available too and
# send through the KC PBX connector.
#
# A blank `from` means "use the default RingCentral channel's own number",
# which is the behaviour everything had before numbers became selectable.
class Kc::OutboundSms
  include Kc::RingcentralAuthRecovery

  RC_AREA   = 'RingCentralSms::Account'.freeze
  PBX_AREA  = 'Freepbx::Account'.freeze

  class << self
    # Every number the system can text from, across all active channels.
    # Shape: [{ number:, label:, channel_id:, provider: 'ringcentral'|'freepbx' }]
    def available_numbers
      (ringcentral_numbers + freepbx_numbers).uniq { |entry| entry[:number] }
    end

    def ringcentral_numbers
      Channel.where(area: RC_AREA, active: true).order(:id).flat_map do |channel|
        opts    = channel.options.with_indifferent_access
        primary = normalize(opts[:phone_number])
        listed  = Array(opts[:available_phone_numbers]).map { |n| normalize(n) }
        account = opts[:user_display_name].presence || opts[:user_email].presence || "Channel #{channel.id}"

        ([primary] + listed).compact.uniq.map do |number|
          {
            number:     number,
            label:      number == primary ? "#{number} (#{account}, default)" : "#{number} (#{account})",
            channel_id: channel.id,
            provider:   'ringcentral',
          }
        end
      end
    end

    def freepbx_sms_enabled?
      Setting.get('kc_freepbx_sms_enabled') == true
    end

    # Numbers the PBX can text from, as last reported by the connector
    # (Kc::PollFreepbxSmsMessagesJob.refresh_sms_numbers caches them).
    def freepbx_numbers
      return [] if !freepbx_sms_enabled?

      Channel.where(area: PBX_AREA, active: true).order(:id).flat_map do |channel|
        opts  = channel.options.with_indifferent_access
        pbx   = opts[:label].presence || 'FreePBX'
        Array(opts[:sms_numbers]).filter_map do |entry|
          entry  = entry.is_a?(Hash) ? entry.with_indifferent_access : { number: entry }
          number = normalize(entry[:number])
          next if number.blank?

          name = [entry[:label].presence, entry[:extension].present? ? "ext #{entry[:extension]}" : nil].compact.join(', ')
          {
            number:     number,
            label:      name.present? ? "#{number} (#{pbx}: #{name})" : "#{number} (#{pbx})",
            channel_id: channel.id,
            provider:   'freepbx',
          }
        end
      end
    end

    # Resolves which RingCentral channel owns a number. Falls back to the
    # configured default channel, then the first active one.
    def channel_for(number)
      channels = Channel.where(area: RC_AREA, active: true).order(:id)
      return nil if channels.empty?

      wanted = normalize(number)
      if wanted.present?
        owner = channels.detect do |channel|
          opts = channel.options.with_indifferent_access
          normalize(opts[:phone_number]) == wanted ||
            Array(opts[:available_phone_numbers]).any? { |n| normalize(n) == wanted }
        end
        return owner if owner
      end

      default_id = Setting.get('kc_ringcentral_sms_default_channel_id').to_s.presence
      (default_id && channels.detect { |c| c.id.to_s == default_id }) || channels.first
    end

    # The FreePBX connection that can text from `number`, or nil.
    def freepbx_channel_for(number)
      wanted = normalize(number)
      return nil if wanted.blank?

      entry = freepbx_numbers.detect { |n| n[:number] == wanted }
      entry && Channel.find_by(id: entry[:channel_id], area: PBX_AREA, active: true)
    end

    # [provider, channel] for the number a caller wants to text from. A
    # FreePBX number wins when it is one; everything else is RingCentral's,
    # including the blank "default" case.
    def provider_channel_for(number)
      pbx = freepbx_channel_for(number)
      return [:freepbx, pbx] if pbx

      rc = channel_for(number)
      rc ? [:ringcentral, rc] : [nil, nil]
    end

    # Ticket preferences that make a ticket reply by text from `from_number`
    # to `customer_number`: { ringcentral_sms: {...} } or { freepbx_sms: {...} }.
    # Returns [prefs_hash, article_type_name] or [nil, nil] when nothing can text.
    def sms_ticket_preferences(from_number, customer_number)
      provider, channel = provider_channel_for(from_number)
      return [nil, nil] if channel.nil?

      our = normalize(from_number).presence
      if provider == :freepbx
        our ||= Array(channel.options.with_indifferent_access[:sms_numbers]).map { |n| n.is_a?(Hash) ? (n[:number] || n['number']) : n }.first
        [{ freepbx_sms: { from_phone: normalize(customer_number), to_phone: normalize(our), channel_id: channel.id } }, 'freepbx_sms_message']
      else
        our ||= channel.options.with_indifferent_access[:phone_number]
        [{ ringcentral_sms: { from_phone: normalize(customer_number), to_phone: normalize(our), channel_id: channel.id } }, 'ringcentral_sms_message']
      end
    end

    def normalize(number)
      return nil if number.blank?

      rc = 'Kc::RingcentralApi'.safe_constantize
      rc ? rc.normalize_phone(number) : number.to_s
    end

    # Message ids of texts the *system* sent (missed-call replies, admin
    # test messages). The outbound pollers capture every text sent from our
    # numbers that Zammad does not already know about, so these have to be
    # recorded or each auto-reply would surface as an agent note / new
    # ticket. Kept as a bounded ring on the channel so no migration is needed.
    SYSTEM_IDS_KEY = :kc_system_sms_ids
    SYSTEM_IDS_MAX = 500

    def remember_system_message(channel, message_id)
      return if channel.nil? || message_id.blank?

      channel.with_lock do
        channel.reload
        ids = Array(channel.options[SYSTEM_IDS_KEY]).map(&:to_s)
        ids << message_id.to_s
        channel.options[SYSTEM_IDS_KEY] = ids.last(SYSTEM_IDS_MAX)
        channel.save!
      end
    rescue StandardError => e
      Rails.logger.warn "KC SMS: could not record system message #{message_id} on channel #{channel&.id}: #{e.message}"
    end

    def system_message?(channel, message_id)
      return false if channel.nil? || message_id.blank?

      Array(channel.options.with_indifferent_access[SYSTEM_IDS_KEY]).map(&:to_s).include?(message_id.to_s)
    end

    # Sends a text. Returns the API result, or nil when it could not be sent.
    # Never raises — callers are background jobs that must keep going.
    def deliver(to:, text:, from: nil, label: 'KC SMS')
      new.deliver(to: to, text: text, from: from, label: label)
    end
  end

  def deliver(to:, text:, from: nil, label: 'KC SMS')
    recipient = self.class.normalize(to)
    if recipient.blank? || text.blank?
      Rails.logger.warn "#{label}: refusing to send, recipient or text is blank"
      return nil
    end

    provider, channel = self.class.provider_channel_for(from)
    if channel.nil?
      Rails.logger.error "#{label}: no active texting channel is configured, cannot text #{recipient}"
      return nil
    end

    result = if provider == :freepbx
               deliver_via_freepbx(channel, recipient, text, from, label)
             else
               deliver_via_ringcentral(channel, recipient, text, from, label)
             end
    return nil if result.nil?

    self.class.remember_system_message(channel, result['id'] || result[:id])
    result
  rescue StandardError => e
    Rails.logger.error "#{label}: failed to text #{to}: #{e.message}"
    nil
  end

  private

  def deliver_via_ringcentral(channel, recipient, text, from, label)
    opts   = channel.options.with_indifferent_access
    sender = self.class.normalize(from).presence || self.class.normalize(opts[:phone_number])
    if sender.blank?
      Rails.logger.error "#{label}: channel #{channel.id} has no usable from-number"
      return nil
    end

    result, _client = rc_call_with_auth_recovery(channel, label) do |client|
      client.send_sms(from: sender, to: recipient, text: text)
    end

    if result.nil?
      Rails.logger.error "#{label}: RingCentral rejected the text to #{recipient} from #{sender}"
      return nil
    end

    Rails.logger.info "#{label}: texted #{recipient} from #{sender} via RingCentral channel #{channel.id}"
    result
  end

  def deliver_via_freepbx(channel, recipient, text, from, label)
    sender = self.class.normalize(from)
    result = Channel::Driver::KcFreepbx.new.deliver(channel.options, { body: text, to_phone: recipient, from_phone: sender }, channel: channel)
    if result.nil?
      Rails.logger.error "#{label}: FreePBX rejected the text to #{recipient} from #{sender}"
      return nil
    end

    Rails.logger.info "#{label}: texted #{recipient} from #{sender} via FreePBX connection #{channel.id}"
    result
  end
end
