# KC: Admin page for Notification Settings.
# Registered under KC Extensions > Notification Settings (prio 4000).
#
# Uses App.SettingsArea to render all settings with area 'Kc::NotificationSettings'.

class KcNotificationSettings extends App.ControllerSubContent
  @requiredPermission: 'admin'
  header: __('Notification Settings')

  constructor: ->
    super
    new App.SettingsArea(
      el:   @el
      area: 'Kc::NotificationSettings'
    )

App.Config.set('KcNotificationSettings', {
  prio:       4000
  name:       __('Notification Settings')
  parent:     '#kc_extensions'
  target:     '#kc_extensions/kc_notification_settings'
  controller: KcNotificationSettings
  permission: ['admin']
}, 'NavBarAdmin')
