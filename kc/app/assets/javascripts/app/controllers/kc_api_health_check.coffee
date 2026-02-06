# KC: Admin page for API Connection Health Check configuration.
# Registered under KC Extensions > API Health Check (prio 3000).
#
# Provides:
#   - Ticket settings configuration (group, priority, owner)
#   - Channel selection for monitoring
#   - Immediate health check trigger

class KcApiHealthCheck extends App.ControllerSubContent
  @requiredPermission: 'admin'
  header: __('API Health Check')

  events:
    'click .js-save':      'save'
    'click .js-checkNow':  'checkNow'
    'change .js-selectAll': 'toggleAll'

  constructor: ->
    super
    @load()

  load: =>
    @startLoading()
    @ajax(
      id:   'kc_api_health_check'
      type: 'GET'
      url:  "#{@apiPath}/kc/api_health_check"
      success: (data) =>
        @stopLoading()
        App.Collection.loadAssets(data.assets)
        @channels    = data.channels || []
        @monitoredIds = data.monitored_channel_ids || []
        @settings =
          group_id:    data.group_id
          priority_id: data.priority_id
          owner_id:    data.owner_id
        @render()
      error: (xhr) =>
        @stopLoading()
        @html '<div class="alert alert--danger">Failed to load API Health Check settings.</div>'
    )

  render: =>
    groups     = App.Group.all().filter (g) -> g.active
    priorities = App.TicketPriority.all().filter (p) -> p.active
    admins     = App.User.all().filter (u) -> u.active && u.permission('admin')

    @html App.view('kc_api_health_check/index')(
      channels:    @channels
      monitoredIds: @monitoredIds
      settings:    @settings
      groups:      groups
      priorities:  priorities
      admins:      admins
    )

  toggleAll: (e) =>
    checked = $(e.currentTarget).is(':checked')
    @el.find('.js-channelCheckbox').prop('checked', checked)

  save: (e) =>
    e.preventDefault()
    btn = $(e.currentTarget)
    btn.prop('disabled', true)

    # Collect checked channel IDs
    monitoredIds = []
    @el.find('.js-channelCheckbox:checked').each ->
      monitoredIds.push(parseInt($(@).val()))

    # Collect ticket settings
    groupId    = @el.find('[name=group_id]').val() || null
    priorityId = @el.find('[name=priority_id]').val() || null
    ownerId    = @el.find('[name=owner_id]').val() || null

    # Convert to int or null
    groupId    = parseInt(groupId) || null
    priorityId = parseInt(priorityId) || null
    ownerId    = parseInt(ownerId) || null

    @ajax(
      id:          'kc_api_health_check_update'
      type:        'PUT'
      url:         "#{@apiPath}/kc/api_health_check"
      data:        JSON.stringify(
        monitored_channel_ids: monitoredIds
        group_id:              groupId
        priority_id:           priorityId
        owner_id:              ownerId
      )
      contentType: 'application/json'
      success: =>
        btn.prop('disabled', false)
        @notify(type: 'success', msg: __('Settings saved.'))
      error: =>
        btn.prop('disabled', false)
        @notify(type: 'error', msg: __('Failed to save settings.'))
    )

  checkNow: (e) =>
    e.preventDefault()
    btn = $(e.currentTarget)
    btn.prop('disabled', true).text(App.i18n.translateInline('Checking…'))

    @ajax(
      id:   'kc_api_health_check_now'
      type: 'POST'
      url:  "#{@apiPath}/kc/api_health_check/check_now"
      success: =>
        btn.prop('disabled', false).text(App.i18n.translateInline('Check Now'))
        @notify(type: 'success', msg: __('Health check queued. Results will appear as tickets if any connection fails.'))
      error: =>
        btn.prop('disabled', false).text(App.i18n.translateInline('Check Now'))
        @notify(type: 'error', msg: __('Failed to trigger health check.'))
    )


# ---------------------------------------------------------------------------
# Register in admin navigation under KC Extensions
# ---------------------------------------------------------------------------
App.Config.set('KcApiHealthCheck', {
  prio:       3000
  name:       __('API Health Check')
  parent:     '#kc_extensions'
  target:     '#kc_extensions/kc_api_health_check'
  controller: KcApiHealthCheck
  permission: ['admin']
}, 'NavBarAdmin')
