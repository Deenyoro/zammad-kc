# KC: Bulk merge from ticket overview.
#
# This controller:
#   1. Injects a "Merge" button into the bulk action bar (next to "Confirmation")
#   2. When clicked, opens a modal with parent ticket search
#   3. On submit, calls POST /api/v1/kc/bulk_merge
#   4. Only shows when kc_bulk_merge setting is enabled
#
# Uses a standalone button (not a state dropdown option) to avoid interference
# with Zammad's CoreWorkflow form handlers which strip non-existent state values.
#
# Registered as a Plugin so it auto-initializes with the application.
class KcBulkMergeHandler extends App.Controller
  constructor: ->
    super
    try
      @startObserver()
      @injectAll()
    catch e
      console.warn '[KC] KcBulkMergeHandler init failed', e

  release: =>
    try
      @stopObserver()
    catch e
      console.warn '[KC] KcBulkMergeHandler release failed', e

  # Use App.Config.get() — frontend settings are delivered via the login
  # response into App.Config, NOT into the App.Setting Spine collection.
  isEnabled: ->
    App.Config.get('kc_bulk_merge') isnt false

  # ---------- DOM injection ----------

  injectAll: =>
    try
      return if !@isEnabled()

      $('.bulkAction-form .js-action-step').each (i, step) =>
        $step = $(step)
        return if $step.find('.js-kc-bulk-merge').length > 0
        mergeBtn = $('<div>')
          .addClass('btn btn--secondary js-kc-bulk-merge')
          .css('margin-left', '10px')
          .text(App.i18n.translateInline('Merge'))
          .on('click', @onMergeClick)
        $step.find('.js-confirm').after(mergeBtn)
    catch e
      console.warn '[KC] injectAll (merge) failed', e

  # ---------- MutationObserver ----------

  startObserver: =>
    return if typeof MutationObserver is 'undefined'
    try
      @observer = new MutationObserver (mutations) =>
        for mutation in mutations
          if mutation.addedNodes?.length > 0
            @delay(@injectAll, 100, 'kc-bulk-merge-inject')
            break

      appEl = document.querySelector('#app')
      @observer.observe(appEl, { childList: true, subtree: true }) if appEl
    catch e
      console.warn '[KC] startObserver failed', e

  stopObserver: =>
    try
      @observer?.disconnect()
      @observer = null
    catch e
      console.warn '[KC] stopObserver failed', e

  # ---------- Merge button click handler ----------

  onMergeClick: (e) =>
    try
      e.preventDefault()
      e.stopPropagation()

      # Read ticket IDs from checked checkboxes (same approach as TicketBulkForm.submit)
      ticketIds = []
      $('.table [name="bulk"]:checked').each (index, element) ->
        id = parseInt($(element).val(), 10)
        ticketIds.push(id) if !isNaN(id)

      if ticketIds.length is 0
        App.Event.trigger('notify', { type: 'error', msg: App.i18n.translateInline('No tickets selected.') })
        return

      new KcBulkMergeModal(ticketIds: ticketIds)
    catch e
      console.warn '[KC] onMergeClick failed', e

App.Config.set('KcBulkMergeHandler', KcBulkMergeHandler, 'Plugins')


# ---------- Modal: parent ticket picker ----------

class KcBulkMergeModal extends App.ControllerModal
  buttonClose: true
  buttonCancel: true
  buttonSubmit: __('Merge')
  head: __('Merge Tickets')
  shown: true
  small: true

  constructor: (options = {}) ->
    @ticketIds = options.ticketIds || []
    @parentTicketId = null
    @ensureStyles()
    super

  ensureStyles: ->
    return if $('#kc-bulk-merge-styles').length > 0
    $('<style id="kc-bulk-merge-styles">').text("""
      .kc-bulk-merge-list {
        list-style: none;
        padding: 0;
        margin: 10px 0 0;
        max-height: 200px;
        overflow-y: auto;
        border: 1px solid #ddd;
        border-radius: 3px;
      }
      .kc-bulk-merge-list-item {
        padding: 8px 12px;
        cursor: pointer;
        border-bottom: 1px solid #eee;
      }
      .kc-bulk-merge-list-item:hover {
        background: #f5f5f5;
      }
      .kc-bulk-merge-list-item--empty {
        padding: 8px 12px;
        color: #999;
        cursor: default;
      }
      .kc-bulk-merge-section-label {
        font-weight: bold;
        margin: 10px 0 5px;
        color: #333;
        font-size: 12px;
      }
      .kc-bulk-merge-section-label--first {
        margin-top: 0;
      }
      .kc-bulk-merge-selected-info {
        margin-top: 10px;
        padding: 8px 12px;
        background: #e8f4e8;
        border-radius: 3px;
      }
    """).appendTo('head')

  content: ->
    el = $('<div>')

    el.append(
      $('<p>').text(App.i18n.translateInline('Select the parent ticket to merge %s ticket(s) into:', @ticketIds.length))
    )

    # --- Selected Tickets section ---
    el.append(
      $('<div>').addClass('kc-bulk-merge-section-label kc-bulk-merge-section-label--first')
        .text(App.i18n.translateInline('Selected Tickets'))
    )

    selectedList = $('<ul>').addClass('kc-bulk-merge-list')
    for ticketId in @ticketIds
      do (ticketId) =>
        ticket = App.Ticket.find(ticketId)
        if ticket
          li = $('<li>')
            .addClass('kc-bulk-merge-list-item')
            .attr('data-ticket-id', ticket.id)
            .text("##{ticket.number} - #{ticket.title}")
            .on('click', => @selectParent(ticket))
          selectedList.append(li)
    el.append(selectedList)

    # --- Search section ---
    el.append(
      $('<div>').addClass('kc-bulk-merge-section-label')
        .text(App.i18n.translateInline('Or search for another ticket:'))
    )

    @searchInput = $('<input>')
      .addClass('form-control')
      .attr('type', 'text')
      .attr('placeholder', App.i18n.translateInline('Search by ticket number or title...'))
      .attr('autocomplete', 'off')

    el.append(@searchInput)

    @resultsList = $('<ul>').addClass('kc-bulk-merge-list').hide()
    el.append(@resultsList)

    @selectedInfo = $('<div>').addClass('kc-bulk-merge-selected-info').hide()
    el.append(@selectedInfo)

    # Bind search after modal render
    @delay(=>
      @searchInput.on('input', @onSearch)
      @searchInput.on('keydown', (e) -> e.stopPropagation() if e.keyCode is 13)
      @searchInput.trigger('focus')
    , 100)

    el

  onSearch: =>
    query = @searchInput.val()?.trim()
    return @resultsList.hide() if !query || query.length < 2
    @delay((=> @doSearch(query)), 300, 'kc-merge-search')

  doSearch: (query) =>
    # Strip ticket_hook prefix (e.g. "Ticket#") for number detection
    ticketHook = App.Config.get('ticket_hook') || ''
    cleanQuery = query
    if ticketHook && cleanQuery.indexOf(ticketHook) is 0
      cleanQuery = cleanQuery.substring(ticketHook.length).trim()

    # Detect numeric query for direct number search
    isNumeric = /^\d+$/.test(cleanQuery)

    requestData = { limit: 10 }

    if isNumeric
      # Use condition parameter for exact number matching via SQL path
      requestData.query = ''
      requestData.condition = JSON.stringify({ 'ticket.number': { operator: 'contains', value: cleanQuery } })
    else
      requestData.query = query

    App.Ajax.request(
      type: 'GET'
      url:  "#{App.Config.get('api_path')}/tickets/search?full=true"
      data: requestData
      success: (data) =>
        try
          App.Collection.loadAssets(data.assets) if data.assets
          tickets = []
          for id in (data.record_ids || [])
            ticket = App.Ticket.find(id)
            tickets.push(ticket) if ticket
          @showResults(tickets)
        catch e
          console.warn '[KC] search parse failed', e
      error: =>
        @resultsList.hide()
    )

  showResults: (tickets) =>
    @resultsList.empty()

    if tickets.length is 0
      @resultsList.append(
        $('<li>').addClass('kc-bulk-merge-list-item--empty')
          .text(App.i18n.translateInline('No tickets found'))
      )
      @resultsList.show()
      return

    for ticket in tickets
      do (ticket) =>
        li = $('<li>')
          .addClass('kc-bulk-merge-list-item')
          .attr('data-ticket-id', ticket.id)
          .text("##{ticket.number} - #{ticket.title}")
          .on('click', => @selectParent(ticket))

        @resultsList.append(li)
    @resultsList.show()

  selectParent: (ticket) =>
    @parentTicketId = ticket.id
    @searchInput.val("##{ticket.number} - #{ticket.title}")
    @selectedInfo.text("\u2192 ##{ticket.number} - #{ticket.title}").show()
    @resultsList.hide()

  onSubmit: (e) =>
    if !@parentTicketId
      App.Event.trigger('notify', { type: 'error', msg: App.i18n.translateInline('Please select a parent ticket.') })
      return

    @formDisable(e)

    App.Ajax.request(
      type:        'POST'
      url:         "#{App.Config.get('api_path')}/kc/bulk_merge"
      data:        JSON.stringify(ticket_ids: @ticketIds, parent_ticket_id: @parentTicketId)
      processData: false
      contentType: 'application/json'
      success: (data) =>
        @close()
        App.Event.trigger('notify', {
          type: 'success'
          msg:  App.i18n.translateInline('Successfully merged %s ticket(s).', data.merged_count)
        })
        # Uncheck all and trigger change so bulk bar hides
        checked = $('.table [name="bulk"]:checked')
        checked.prop('checked', false)
        checked.first().trigger('change')
        App.Event.trigger('overview:fetch')
      error: (xhr) =>
        try
          msg = JSON.parse(xhr.responseText).error || App.i18n.translateInline('Merge failed.')
        catch
          msg = App.i18n.translateInline('Merge failed.')
        App.Event.trigger('notify', { type: 'error', msg: msg })
        @formEnable(e)
    )
