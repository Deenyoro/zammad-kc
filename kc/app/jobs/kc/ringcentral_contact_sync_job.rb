# KC: Syncs contacts between Zammad and the RingCentral address book of each
# active RingCentral SMS channel that has contact import or export turned on
# (channel options contact_import / contact_export, both off by default).
# See Kc::RingcentralContactSync for what is synced and how.
#
# Runs every 6 hours from the scheduler ("Sync RingCentral contacts.") and
# from the "Sync contacts now" button on the RingCentral SMS admin page.
#
# One run per channel at a time (HasActiveJobLock), so the scheduler and the
# button cannot write the same contacts twice. No retry_on: every run
# re-reads the address book and picks up where the last one stopped, and
# errors are recorded on the channel (options[:last_contact_sync]).
class Kc::RingcentralContactSyncJob < ApplicationJob
  include HasActiveJobLock

  CHANNEL_AREA = 'RingCentralSms::Account'.freeze

  def lock_key
    "#{self.class.name}/#{arguments[0] || 'all'}"
  end

  # @param channel_id [Integer, nil] one channel, or nil for every active
  #   channel with import or export enabled.
  def perform(channel_id = nil)
    sync_class = 'Kc::RingcentralContactSync'.safe_constantize
    return if sync_class.nil?

    channels(channel_id).each do |channel|
      sync = sync_class.new(channel)
      next if !sync.import_enabled? && !sync.export_enabled?

      result = sync.run
      Rails.logger.info "KC RingCentral Contact Sync: channel #{channel.id} #{result[:status]} — " \
                        "import=#{result[:import].inspect} export=#{result[:export].inspect}"
    rescue => e
      Rails.logger.error "KC RingCentral Contact Sync: channel #{channel.id} failed: #{e.message}"
    end
  end

  private

  def channels(channel_id)
    scope = Channel.where(area: CHANNEL_AREA, active: true).reorder(:id)
    scope = scope.where(id: channel_id) if channel_id.present?
    scope.to_a
  end
end
