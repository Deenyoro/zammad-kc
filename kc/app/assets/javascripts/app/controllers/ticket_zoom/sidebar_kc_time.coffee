# KC: Sidebar tab for per-agent time tracking.
#
# Registers as a TicketZoomSidebar backend — appears as a clock-icon tab
# alongside ticket, customer, organization, and checklist.
#
# HARDENING:
#   - KC API 404 → tab hides permanently for this page session
#   - Missing upstream classes (App.User, App.TicketTimeAccountingType,
#     App.TimeAccountingUnitMixin) → guarded with try/catch, never crashes
#   - All AJAX errors → user notification, never crashes sidebar
#   - sidebarItem() wrapped in try/catch — if ticket or currentView is
#     missing the tab simply doesn't appear
#   - render() wrapped in try/catch — a template error shows a fallback
#     message instead of breaking the sidebar
#   - Event handlers wrapped in try/catch — a broken handler logs a
#     console.warn and does not propagate
#
# NOTE: TicketZoomSidebar backends are instantiated WITHOUT an `el` param.
# The sidebar content element is passed later via `sidebarCallback(el)`.
# Spine's `events` hash delegates on `@el` which is a detached <div>,
# so we bind events manually on `@elSidebar` after each render instead.

class SidebarKcTime extends App.Controller
  @include App.TimeAccountingUnitMixin if App.TimeAccountingUnitMixin

  constructor: ->
    super
    @kcAvailable    = true
    @kcEntries      = []
    @showAddForm    = false
    @showAllEntries = false

  sidebarItem: =>
    try
      return if !@kcAvailable
      return if !@ticket
      return if typeof @ticket.currentView isnt 'function'
      return if @ticket.currentView() isnt 'agent'
    catch e
      console.warn '[KC] sidebar_kc_time.sidebarItem: guard check failed', e
      return

    @item = {
      name:           'kc_time'
      badgeCallback:  @badgeRender
      sidebarHead:    __('Time Tracking')
      sidebarCallback: @sidebarCallback
    }

  sidebarCallback: (el) =>
    @elSidebar = el
    @elSidebar.html('<div class="sidebar-loading"><span class="loading icon"></span></div>')

  shown: =>
    @fetchKcEntries()

  # ---------- Badge ----------

  metaBadge: =>
    {
      name:             'kc_time'
      icon:             'clock'
      counterPossible:  true
      counter:          if @kcEntries.length > 0 then @kcEntries.length else undefined
    }

  badgeRender: (el) =>
    @badgeEl = el
    @badgeRenderLocal()

  badgeRenderLocal: =>
    try
      return if !@badgeEl
      @badgeEl.html(App.view('generic/sidebar_tabs_item')(@metaBadge()))
    catch e
      console.warn '[KC] sidebar_kc_time.badgeRenderLocal failed', e

  # ---------- Data fetching ----------

  fetchKcEntries: =>
    try
      @ajax(
        id:   "kc_sidebar_time_#{@ticket.id}"
        type: 'GET'
        url:  "#{@apiPath}/kc/tickets/#{@ticket.id}/time_entries"
        success: (data) =>
          @kcEntries = if Array.isArray(data) then data else []
          @render()
          @badgeRenderLocal()
        error: (xhr) =>
          if xhr.status is 404
            console.warn('[KC] Time tracking API not available (404) — hiding sidebar tab')
            @kcAvailable = false
            try
              App.Event.trigger('ui::ticket::sidebarRerender', { taskKey: @taskKey })
            catch
              # sidebarRerender event not handled — tab stays but content is empty
          else
            console.warn("[KC] Time tracking API error (#{xhr.status})")
            @kcEntries = []
            @render()
      )
    catch e
      console.warn '[KC] sidebar_kc_time.fetchKcEntries failed', e
      @kcEntries = []
      @render()

  # ---------- Rendering ----------

  render: =>
    return if !@elSidebar

    try
      agentGroups = @groupByAgent(@kcEntries)

      agents = []
      try
        allUsers = App.User?.search?(sortBy: 'firstname', order: 'ASC') || []
        for user in allUsers
          if user.active && user.permission?('ticket.agent')
            agents.push(user)
      catch e
        console.warn '[KC] sidebar_kc_time: agent lookup failed', e

      types = []
      try
        types = App.TicketTimeAccountingType?.all?() || []
      catch
        types = []

      displayUnit = null
      try
        displayUnit = @timeAccountingDisplayUnit?() || null
      catch
        displayUnit = null

      editable = false
      try
        editable = @ticket.editable?() || false
      catch
        editable = false

      total = 0
      for entry in @kcEntries
        total += parseFloat(entry.time_unit) if entry.time_unit

      @elSidebar.html(App.view('ticket_zoom/kc_time_sidebar')(
        entries:        @kcEntries
        agentGroups:    agentGroups
        total:          total
        displayUnit:    displayUnit
        showMore:       @kcEntries.length > 10 && !@showAllEntries
        showAllEntries: @showAllEntries
        showAddForm:    @showAddForm
        agents:         agents
        types:          types
        editable:       editable
      ))

      @bindSidebarEvents()

    catch e
      console.warn '[KC] sidebar_kc_time.render failed', e
      try
        @elSidebar.html('<div class="text-muted" style="padding: 10px;">Time tracking could not be loaded.</div>')
      catch
        # elSidebar itself is broken — nothing we can do

  bindSidebarEvents: =>
    return if !@elSidebar
    @elSidebar.off('.kcTime')
    @elSidebar.on('click.kcTime', '.js-toggleAddForm',   (e) => @_safe('toggleAddForm', e))
    @elSidebar.on('click.kcTime', '.js-addEntry',        (e) => @_safe('addEntry', e))
    @elSidebar.on('click.kcTime', '.js-deleteEntry',     (e) => @_safe('deleteEntry', e))
    @elSidebar.on('click.kcTime', '.js-showMoreEntries', (e) => @_safe('showMore', e))

  # Wraps event handler calls in try/catch so a broken handler never
  # crashes the rest of the sidebar.
  _safe: (method, e) =>
    try
      @[method](e)
    catch err
      console.warn "[KC] sidebar_kc_time.#{method} failed", err

  # ---------- Helpers ----------

  groupByAgent: (entries) ->
    groups = {}
    for entry in (entries || [])
      key = entry.agent_id || 'unknown'
      if !groups[key]
        groups[key] =
          agent_id:   entry.agent_id
          agent_name: entry.agent_name || __('Unknown')
          total:      0
          entries:    []
      groups[key].total += parseFloat(entry.time_unit) || 0
      groups[key].entries.push(entry)

    result = []
    for key, group of groups
      result.push(group)
    result.sort((a, b) -> b.total - a.total)
    result

  # ---------- Actions ----------

  showMore: (e) ->
    e.preventDefault()
    e.stopPropagation()
    @showAllEntries = true
    @render()

  toggleAddForm: (e) ->
    e.preventDefault()
    e.stopPropagation()
    @showAddForm = !@showAddForm
    @render()

  addEntry: (e) ->
    e.preventDefault()
    e.stopPropagation()

    agentId  = @elSidebar.find('.js-agentSelect').val()
    typeId   = @elSidebar.find('.js-typeSelect').val()
    timeUnit = @elSidebar.find('.js-timeInput').val()

    if !timeUnit || parseFloat(timeUnit) <= 0
      @notify(
        type: 'error'
        msg:  __('Please enter a valid time value')
      )
      return

    @ajax(
      id:   "kc_sidebar_time_create_#{@ticket.id}"
      type: 'POST'
      url:  "#{@apiPath}/kc/tickets/#{@ticket.id}/time_entries"
      data: JSON.stringify(
        agent_id:  agentId
        type_id:   typeId || null
        time_unit: parseFloat(timeUnit)
      )
      processData: true
      success: =>
        @showAddForm = false
        @fetchKcEntries()
      error: (xhr) =>
        @notify(
          type: 'error'
          msg:  xhr.responseJSON?.error || __('Failed to add time entry')
        )
    )

  deleteEntry: (e) ->
    e.preventDefault()
    e.stopPropagation()
    entryId = $(e.currentTarget).data('entry-id')

    @ajax(
      id:   "kc_sidebar_time_delete_#{entryId}"
      type: 'DELETE'
      url:  "#{@apiPath}/kc/tickets/#{@ticket.id}/time_entries/#{entryId}"
      success: =>
        @fetchKcEntries()
      error: (xhr) =>
        @notify(
          type: 'error'
          msg:  xhr.responseJSON?.error || __('Failed to delete time entry')
        )
    )

App.Config.set('500-KcTime', SidebarKcTime, 'TicketZoomSidebar')
