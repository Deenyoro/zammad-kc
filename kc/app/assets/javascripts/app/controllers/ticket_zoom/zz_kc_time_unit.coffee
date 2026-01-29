# KC: Extend upstream TicketZoomTimeUnit to show per-user time breakdown
# with inline add/delete functionality.
#
# This file is named zz_kc_* so Sprockets loads it AFTER the upstream
# time_unit.coffee.
#
# HARDENING STRATEGY:
#
#   1. EXTENDS, not replaces — we save the original class and subclass it.
#      New upstream methods, constructor logic, and properties are inherited
#      automatically via the prototype chain.
#
#   2. EVENTS MERGE automatically — Spine.Controller walks __super__ and
#      calls $.extend() to merge parent events into child events. We only
#      declare our KC-specific events; upstream events are inherited.
#
#   3. GRACEFUL FALLBACK — if the KC API returns 404 (routes not loaded,
#      backend mismatch, etc.), the widget permanently falls back to the
#      upstream render for that page session. The sidebar never breaks.
#
#   4. UPSTREAM RENDER preserved — we keep a reference to the original
#      render method and delegate to it whenever KC mode is unavailable.
#
#   Remaining surface area: our render() replaces the upstream template.
#   If upstream changes the *caller contract* in sidebar_ticket.coffee
#   (constructor args or reload signature), a manual update is needed.
#   The upstream class has been stable since Zammad 5.x.

# ---- Save upstream class and its render before we redefine the name ----
# Guard: if upstream removed the class entirely, define a minimal stub so the
# rest of this file doesn't throw.  The sidebar simply won't render.
if typeof App.TicketZoomTimeUnit is 'undefined'
  console.warn '[KC] App.TicketZoomTimeUnit not found — upstream may have removed or renamed it. KC time unit sidebar disabled.'
  class App.TicketZoomTimeUnit extends App.Controller
    reload: -> # no-op
    render: -> # no-op

_OriginalTimeUnit       = App.TicketZoomTimeUnit
_originalTimeUnitRender = _OriginalTimeUnit::render

class App.TicketZoomTimeUnit extends _OriginalTimeUnit

  # Only KC-specific events — upstream events (js-showMoreEntries, etc.)
  # are merged in automatically by Spine's __super__ chain walk.
  events:
    'click .js-toggleAddForm':  'toggleAddForm'
    'click .js-addEntry':       'addEntry'
    'click .js-deleteEntry':    'deleteEntry'

  constructor: ->
    @kcAvailable = true    # optimistic — flipped to false on 404
    @showAddForm = false
    @kcEntries   = []
    super

  reload: (time_accountings) =>
    @time_accountings = time_accountings
    if @kcAvailable
      @fetchKcEntries()
    else
      @renderUpstream()

  # ---------- KC data fetching ----------

  fetchKcEntries: =>
    @ajax(
      id:    "kc_time_entries_#{@object_id}"
      type:  'GET'
      url:   "#{@apiPath}/kc/tickets/#{@object_id}/time_entries"
      success: (data) =>
        @kcEntries = data
        @render()
      error: (xhr) =>
        if xhr.status is 404
          # KC backend not available — fall back permanently for this session
          console.warn('KC TimeManagement: API not available (404), falling back to upstream widget')
          @kcAvailable = false
          @renderUpstream()
        else
          # Transient error — render with empty entries
          @kcEntries = []
          @render()
    )

  # ---------- Rendering ----------

  renderUpstream: =>
    _originalTimeUnitRender.call(@)

  render: =>
    if !@kcAvailable
      @renderUpstream()
      return

    try
      ticket = App.Ticket.find(@object_id)
    catch e
      console.warn '[KC] TicketZoomTimeUnit.render: ticket lookup failed', e
      return

    return if ticket.currentView() isnt 'agent'
    return if !ticket.time_unit

    agentGroups = @groupByAgent(@kcEntries)

    agents = App.User.search(sortBy: 'firstname', order: 'ASC')
    agentList = []
    for agent in agents
      if agent.active && agent.permission('ticket.agent')
        agentList.push(agent)

    # Guard: App.TicketTimeAccountingType may be removed or renamed upstream
    types = []
    try
      types = App.TicketTimeAccountingType?.all?() || []
    catch
      types = []

    @html App.view('ticket_zoom/kc_time_unit')(
      ticket:         ticket
      displayUnit:    @timeAccountingDisplayUnit()
      agentGroups:    agentGroups
      showMore:       @kcEntries.length > 10 && !@showAllEntries
      showAllEntries: @showAllEntries
      showAddForm:    @showAddForm
      agents:         agentList
      types:          types
      editable:       ticket.editable()
    )

  # ---------- KC-specific helpers ----------

  groupByAgent: (entries) ->
    groups = {}
    for entry in entries
      key = entry.agent_id
      if !groups[key]
        groups[key] =
          agent_id:   entry.agent_id
          agent_name: entry.agent_name
          total:      0
          entries:    []
      groups[key].total += parseFloat(entry.time_unit)
      groups[key].entries.push(entry)

    result = []
    for key, group of groups
      result.push(group)
    result.sort((a, b) -> b.total - a.total)
    result

  toggleAddForm: (e) ->
    @preventDefaultAndStopPropagation(e)
    @showAddForm = !@showAddForm
    @render()

  addEntry: (e) ->
    @preventDefaultAndStopPropagation(e)

    agentId  = @$('.js-agentSelect').val()
    typeId   = @$('.js-typeSelect').val()
    timeUnit = @$('.js-timeInput').val()

    if !timeUnit || parseFloat(timeUnit) <= 0
      return

    @ajax(
      id:   "kc_time_entry_create_#{@object_id}"
      type: 'POST'
      url:  "#{@apiPath}/kc/tickets/#{@object_id}/time_entries"
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
          msg:  xhr.responseJSON?.error || 'Failed to add time entry'
        )
    )

  deleteEntry: (e) ->
    @preventDefaultAndStopPropagation(e)
    entryId = $(e.currentTarget).data('entry-id')

    @ajax(
      id:   "kc_time_entry_delete_#{entryId}"
      type: 'DELETE'
      url:  "#{@apiPath}/kc/tickets/#{@object_id}/time_entries/#{entryId}"
      success: =>
        @fetchKcEntries()
      error: (xhr) =>
        @notify(
          type: 'error'
          msg:  xhr.responseJSON?.error || 'Failed to delete time entry'
        )
    )
