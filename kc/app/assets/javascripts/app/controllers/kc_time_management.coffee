# KC: Admin page for Time Management reporting.
# Registered under KC Extensions > Time Management.
#
# This file also registers the "KC Extensions" top-level admin section
# and its route handler. All KC admin pages should use parent: '#kc_extensions'.
#
# Hardening: The @include of App.TimeAccountingUnitMixin is guarded — if
# upstream removes or renames it the controllers still render (they just
# won't have the unit-formatting helper).  API errors are shown inline.

# ---------- Route handler for KC Extensions section ----------
# Mirrors Zammad's ManageRouter pattern for admin section navigation.

class KcExtensionsRouter extends App.ControllerPermanent
  @requiredPermission: ['admin']

  constructor: (params) ->
    super
    @authenticateCheckRedirect()

    App.TaskManager.execute(
      key:        'KcExtensions'
      controller: 'Manage'
      params:     params
      show:       true
      persistent: true
    )

App.Config.set('kc_extensions/:target', KcExtensionsRouter, 'Routes')

# ---------- Top-level admin section ----------

App.Config.set('KcExtensions', {
  prio:       8500
  name:       __('KC Extensions')
  target:     '#kc_extensions'
  permission: ['admin']
}, 'NavBarAdmin')

# ---------- Time Management controller ----------

class KcTimeManagement extends App.ControllerTabs
  @requiredPermission: 'admin'
  header: __('Time Management')

  constructor: ->
    super

    @tabs = [
      {
        name:       __('By User')
        target:     'by_user'
        controller: KcTimeManagementByUser
      },
      {
        name:       __('By Organization')
        target:     'by_organization'
        controller: KcTimeManagementByOrganization
      },
    ]

    @render()

class KcTimeManagementByUser extends App.Controller
  # Guard: upstream may remove or rename this mixin
  if App.TimeAccountingUnitMixin
    @include App.TimeAccountingUnitMixin

  events:
    'click .js-timePickerYear':  'setYear'
    'click .js-timePickerMonth': 'setMonth'

  constructor: ->
    super
    current = new Date()
    @month = current.getMonth() + 1
    @year  = current.getFullYear()
    @render()

  render: =>
    year           = new Date().getFullYear()
    timeRangeYear  = [year-2..year]
    timeRangeMonth = [__('Jan'), __('Feb'), __('Mar'), __('Apr'), __('May'), __('Jun'), __('Jul'), __('Aug'), __('Sep'), __('Oct'), __('Nov'), __('Dec')]

    @html App.view('kc_time_management/by_user')(
      month:          @month
      year:           @year
      timeRangeYear:  timeRangeYear
      timeRangeMonth: timeRangeMonth
    )

    @load()

  load: =>
    @ajax(
      id:    'kc_time_management_by_user'
      type:  'GET'
      url:   "#{@apiPath}/kc/time_management/by_user/#{@year}/#{@month}"
      success: (data) =>
        @$('.js-tableByUser').html App.view('kc_time_management/by_user_table')(
          rows: data
        )
      error: (xhr) =>
        @$('.js-tableByUser').html('<div class="text-muted">Failed to load data.</div>')
    )

  setYear: (e) =>
    e.preventDefault()
    @year = $(e.target).data('type')
    @render()

  setMonth: (e) =>
    e.preventDefault()
    @month = $(e.target).data('type')
    @render()

class KcTimeManagementByOrganization extends App.Controller
  # Guard: upstream may remove or rename this mixin
  if App.TimeAccountingUnitMixin
    @include App.TimeAccountingUnitMixin

  events:
    'click .js-timePickerYear':  'setYear'
    'click .js-timePickerMonth': 'setMonth'

  constructor: ->
    super
    current = new Date()
    @month = current.getMonth() + 1
    @year  = current.getFullYear()
    @render()

  render: =>
    year           = new Date().getFullYear()
    timeRangeYear  = [year-2..year]
    timeRangeMonth = [__('Jan'), __('Feb'), __('Mar'), __('Apr'), __('May'), __('Jun'), __('Jul'), __('Aug'), __('Sep'), __('Oct'), __('Nov'), __('Dec')]

    @html App.view('kc_time_management/by_organization')(
      month:          @month
      year:           @year
      timeRangeYear:  timeRangeYear
      timeRangeMonth: timeRangeMonth
    )

    @load()

  load: =>
    @ajax(
      id:    'kc_time_management_by_organization'
      type:  'GET'
      url:   "#{@apiPath}/kc/time_management/by_organization/#{@year}/#{@month}"
      success: (data) =>
        @$('.js-tableByOrganization').html App.view('kc_time_management/by_organization_table')(
          rows: data
        )
      error: (xhr) =>
        @$('.js-tableByOrganization').html('<div class="text-muted">Failed to load data.</div>')
    )

  setYear: (e) =>
    e.preventDefault()
    @year = $(e.target).data('type')
    @render()

  setMonth: (e) =>
    e.preventDefault()
    @month = $(e.target).data('type')
    @render()

App.Config.set('KcTimeManagement', {
  prio:       1000
  name:       __('Time Management')
  parent:     '#kc_extensions'
  target:     '#kc_extensions/kc_time_management'
  controller: KcTimeManagement
  permission: ['admin']
}, 'NavBarAdmin')
