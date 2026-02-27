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

  # Safe setting check — App.Setting.get() throws if the setting doesn't
  # exist in the frontend collection (e.g. migration hasn't run yet).
  isEnabled: ->
    try
      return App.Setting.get('kc_bulk_merge') isnt false
    catch
      true

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
    super

  content: ->
    el = $('<div>')

    el.append(
      $('<p>').text(App.i18n.translateInline('Select the parent ticket to merge %s ticket(s) into:', @ticketIds.length))
    )

    @searchInput = $('<input>')
      .addClass('form-control')
      .attr('type', 'text')
      .attr('placeholder', App.i18n.translateInline('Search by ticket number or title...'))
      .attr('autocomplete', 'off')

    el.append(@searchInput)

    @resultsList = $('<ul>').css(
      'list-style':    'none'
      'padding':       '0'
      'margin':        '10px 0 0'
      'max-height':    '200px'
      'overflow-y':    'auto'
      'border':        '1px solid #ddd'
      'border-radius': '3px'
      'display':       'none'
    )
    el.append(@resultsList)

    @selectedInfo = $('<div>').css(
      'display':       'none'
      'margin-top':    '10px'
      'padding':       '8px 12px'
      'background':    '#e8f4e8'
      'border-radius': '3px'
    )
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
    App.Ajax.request(
      type: 'GET'
      url:  "#{App.Config.get('api_path')}/tickets/search"
      data: { query: query, limit: 10 }
      success: (data) =>
        try
          App.Collection.loadAssets(data.assets) if data.assets
          tickets = []
          for id in (data.tickets || [])
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
        $('<li>').css({ padding: '8px 12px', color: '#999' })
          .text(App.i18n.translateInline('No tickets found'))
      )
      @resultsList.show()
      return

    for ticket in tickets
      do (ticket) =>
        li = $('<li>').css(
          'padding':       '8px 12px'
          'cursor':        'pointer'
          'border-bottom': '1px solid #eee'
        ).attr('data-ticket-id', ticket.id)
          .text("##{ticket.number} - #{ticket.title}")
          .on('mouseenter', -> $(this).css('background', '#f5f5f5'))
          .on('mouseleave', -> $(this).css('background', '#fff'))
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
