# KC: Admin page for Time Management reporting.
# Registered under System > KC - Time Management.
#
# Hardening: The @include of App.TimeAccountingUnitMixin is guarded — if
# upstream removes or renames it the controllers still render (they just
# won't have the unit-formatting helper).  API errors are shown inline.

class KcTimeManagement extends App.ControllerTabs
  @requiredPermission: 'admin'
  header: __('KC - Time Management')

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

App.Config.set('KcTimeManagement', { prio: 8600, name: __('KC - Time Management'), parent: '#system', target: '#system/kc_time_management', controller: KcTimeManagement, permission: ['admin'] }, 'NavBarAdmin')
