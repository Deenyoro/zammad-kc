# KC: Fix setting permissions so agents can read KC settings.
#
# The original migrations set preferences[:permission] = ['admin'], which
# blocks agents from seeing these settings in App.Setting (Pundit's
# SettingPolicy filters them out). Since agents need these settings for the
# frontend features to work, we remove the permission restriction.
#
# Also updates the original migration files so fresh installs get it right.
class FixKcSettingsAgentVisibility < ActiveRecord::Migration[7.0]
  def up
    %w[kc_strip_email_text_color kc_bulk_merge].each do |name|
      setting = Setting.find_by(name: name)
      next if setting.nil?

      prefs = setting.preferences || {}
      prefs.delete(:permission)
      prefs.delete('permission')
      setting.update!(preferences: prefs)
    end
  end
end
