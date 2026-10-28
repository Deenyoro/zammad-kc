# KC: RingCentral contact sync (Kc::RingcentralContactSyncJob).
#
# - Per-channel switches contact_import / contact_export on every existing
#   RingCentral SMS channel, both off. An administrator turns them on in
#   Admin > KC Extensions > RingCentral SMS > Edit. Channels created later
#   have no key, which also means off.
# - Scheduler entry running the sync every 6 hours. It only does work for
#   channels with a switch on. perform_later hands the run to the background
#   worker, because throttled address-book writes can take several minutes.
#
# Safety:
#   - Idempotent: create_if_not_exists, and a switch already present on a
#     channel is left as it is
class AddKcRingcentralContactSync < ActiveRecord::Migration[7.0]
  CHANNEL_AREA   = 'RingCentralSms::Account'.freeze
  SCHEDULER_NAME = 'Sync RingCentral contacts.'.freeze
  OPTION_KEYS    = %w[contact_import contact_export].freeze

  def up
    return if !Setting.exists?(name: 'system_init_done')

    Channel.where(area: CHANNEL_AREA).find_each do |channel|
      options = channel.options || {}
      missing = OPTION_KEYS.reject { |key| options.key?(key) || options.key?(key.to_sym) }
      next if missing.empty?

      missing.each { |key| options[key] = false }
      channel.update_columns(options: options) # rubocop:disable Rails/SkipsModelValidations
    end

    Scheduler.create_if_not_exists(
      name:          SCHEDULER_NAME,
      method:        'Kc::RingcentralContactSyncJob.perform_later',
      period:        6.hours,
      prio:          4,
      active:        true,
      updated_by_id: 1,
      created_by_id: 1,
      last_run:      Time.current,
    )
  end

  def down
    Scheduler.find_by(name: SCHEDULER_NAME)&.destroy

    Channel.where(area: CHANNEL_AREA).find_each do |channel|
      options = channel.options || {}
      keys = OPTION_KEYS + %w[last_contact_sync]
      next if keys.none? { |key| options.key?(key) || options.key?(key.to_sym) }

      keys.each do |key|
        options.delete(key)
        options.delete(key.to_sym)
      end
      channel.update_columns(options: options) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
