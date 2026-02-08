# KC: Admin page for General KC Settings.
# Registered under KC Extensions > General (prio 1000).
#
# Uses App.SettingsArea to render all settings with area 'Kc::General'.

class KcGeneralSettings extends App.ControllerSubContent
  @requiredPermission: 'admin'
  header: __('General')

  constructor: ->
    super
    new App.SettingsArea(
      el:   @el
      area: 'Kc::General'
    )

App.Config.set('KcGeneralSettings', {
  prio:       1000
  name:       __('General')
  parent:     '#kc_extensions'
  target:     '#kc_extensions/kc_general'
  controller: KcGeneralSettings
  permission: ['admin']
}, 'NavBarAdmin')
