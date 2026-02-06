# KC: Fix suppress note notification settings area for admin UI rendering.
#
# The original migration used area 'Kc::Extensions' which has no admin
# controller. This corrective migration changes it to 'Kc::NotificationSettings'
# which has a dedicated admin page.
class FixKcSuppressNoteNotificationsArea < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    %w[
      kc_suppress_internal_note_notifications
      kc_suppress_all_note_notifications
    ].each do |name|
      setting = Setting.find_by(name: name)
      next if setting.nil?

      setting.update!(area: 'Kc::NotificationSettings')
    end
  end

  def down
    # No-op — original migration handles cleanup
  end
end
