# KC: Fix suppress note notification settings to be visible in admin UI.
#
# The original migration (20260207000003) set frontend: false, which hides
# the settings from the admin panel. This corrective migration flips them
# to frontend: true.
class FixKcSuppressNoteNotificationsFrontend < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    %w[
      kc_suppress_internal_note_notifications
      kc_suppress_all_note_notifications
    ].each do |name|
      setting = Setting.find_by(name: name)
      next if setting.nil?

      setting.update!(frontend: true)
    end
  end

  def down
    # No-op — original migration handles cleanup
  end
end
