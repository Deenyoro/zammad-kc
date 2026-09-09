# KC: One place to send an SMS from any number configured in the system.
#
# RingCentral owns texting for the whole phone system, so every outbound
# SMS — whether the trigger was a RingCentral missed call, a FreePBX missed
# call, or anything added later — is sent through a RingCentral channel.
# The caller says which number it wants to text *from*; this service finds
# the channel that owns that number and sends through it.
#
# A blank `from` means "use the default channel's own number", which is the
# behaviour everything had before numbers became selectable.
class Kc::OutboundSms
  include Kc::RingcentralAuthRecovery

  RC_AREA = 'RingCentralSms::Account'.freeze

  class << self
    # Every number the system can text from, across all active channels.
    # Shape: [{ number:, label:, channel_id: }]
    def available_numbers
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
          }
        end
      end.uniq { |entry| entry[:number] }
    end

    # Resolves which channel owns a number. Falls back to the configured
    # default channel, then the first active one.
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

    def normalize(number)
      return nil if number.blank?

      rc = 'Kc::RingcentralApi'.safe_constantize
      rc ? rc.normalize_phone(number) : number.to_s
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

    channel = self.class.channel_for(from)
    if channel.nil?
      Rails.logger.error "#{label}: no active RingCentral channel is configured, cannot text #{recipient}"
      return nil
    end

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

    Rails.logger.info "#{label}: texted #{recipient} from #{sender} via channel #{channel.id}"
    result
  rescue StandardError => e
    Rails.logger.error "#{label}: failed to text #{to}: #{e.message}"
    nil
  end
end
