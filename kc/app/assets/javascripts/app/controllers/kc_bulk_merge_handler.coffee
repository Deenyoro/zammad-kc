# KC: Bulk merge from ticket overview.
#
# This controller:
#   1. Injects a "merge" option into the bulk action state dropdown
#   2. When selected, shows a parent ticket search input
#   3. On submit, calls POST /api/v1/kc/bulk_merge
#   4. Only shows when kc_bulk_merge setting is enabled
#
# Registered as a Plugin so it auto-initializes with the application.
#
# HARDENING:
#   - All DOM manipulation wrapped in try/catch
#   - MutationObserver with debounce for re-injection on DOM changes
#   - Reset behavior when "merge" is deselected or bulk bar hides
#   - Safe DOM element construction (no raw HTML string concatenation)
class KcBulkMergeHandler extends App.Controller
  constructor: ->
    super
    try
      @mergeMode = false
      @parentTicketId = null
      @searchResults = []

      # Watch for DOM changes
      @startObserver()

      # Inject into existing dropdowns
      @injectAll()

      # Listen for state dropdown changes
      $(document).on('change.kcBulkMerge', '#form-ticket-bulk select[name="state_id"]', @onStateChange)
    catch e
      console.warn '[KC] KcBulkMergeHandler init failed', e

  release: =>
    try
      @mergeMode = false
      @parentTicketId = null
      $(document).off('.kcBulkMerge')
      @stopObserver()
      @removeMergeUI()
    catch e
      console.warn '[KC] KcBulkMergeHandler release failed', e

  # ---------- DOM injection ----------

  injectAll: =>
    try
      return if !App.Setting.get('kc_bulk_merge')

      $('#form-ticket-bulk select[name="state_id"]').each (i, select) =>
        @injectIntoSelect($(select))
    catch e
      console.warn '[KC] injectAll (merge) failed', e

  injectIntoSelect: (select) =>
    return if !select || select.length is 0
    return if select.find('option[value="kc_merge"]').length > 0

    mergeOption = $('<option>')
      .attr('value', 'kc_merge')
      .text(App.i18n.translateInline('Merge into...'))

    select.append(mergeOption)

  # ---------- MutationObserver ----------

  startObserver: =>
    return if typeof MutationObserver is 'undefined'
    try
      @observer = new MutationObserver (mutations) =>
        needsInject = false
        for mutation in mutations
          if mutation.addedNodes?.length > 0
            needsInject = true
            break
        if needsInject
          @delay(@injectAll, 300, 'kc-bulk-merge-inject')

      appEl = document.querySelector('#app')
      if appEl
        @observer.observe(appEl, { childList: true, subtree: true })
    catch e
      console.warn '[KC] startObserver (merge) failed', e

  stopObserver: =>
    try
      @observer?.disconnect()
      @observer = null
    catch e
      console.warn '[KC] stopObserver (merge) failed', e

  # ---------- State change handler ----------

  onStateChange: (e) =>
    try
      select = $(e.currentTarget)
      if select.val() is 'kc_merge'
        @enterMergeMode(select)
      else if @mergeMode
        @exitMergeMode(select)
    catch e
      console.warn '[KC] onStateChange (merge) failed', e

  # ---------- Merge mode ----------

  enterMergeMode: (stateSelect) =>
    @mergeMode = true
    @parentTicketId = null

    bulkForm = stateSelect.closest('.bulkAction-form')
    return if bulkForm.length is 0

    # Hide normal bulk form fields (group, owner, priority, etc.) except state
    bulkForm.find('#form-ticket-bulk .form-group').each ->
      el = $(this)
      attrName = el.data('attribute-name')
      if attrName and attrName isnt 'state_id'
        el.addClass('kc-bulk-merge-hidden hide')

    # Hide the normal confirm button
    bulkForm.find('.js-confirm').addClass('kc-bulk-merge-hidden hide')

    # Inject merge UI after state dropdown
    @buildMergeUI(bulkForm)

  exitMergeMode: (stateSelect) =>
    @mergeMode = false
    @parentTicketId = null

    bulkForm = stateSelect.closest('.bulkAction-form')
    return if bulkForm.length is 0

    @removeMergeUI()

    # Restore hidden fields
    bulkForm.find('.kc-bulk-merge-hidden').removeClass('kc-bulk-merge-hidden hide')

  buildMergeUI: (bulkForm) =>
    # Remove any existing merge UI
    $('.kc-bulk-merge-ui').remove()

    container = $('<div>').addClass('kc-bulk-merge-ui form-group').css({
      'display': 'flex'
      'align-items': 'center'
      'gap': '10px'
      'flex': '1'
    })

    # Parent ticket search input
    inputWrap = $('<div>').addClass('kc-bulk-merge-search-wrap').css({
      'position': 'relative'
      'flex': '1'
    })

    @searchInput = $('<input>')
      .addClass('form-control kc-bulk-merge-search')
      .attr('type', 'text')
      .attr('placeholder', App.i18n.translateInline('Search parent ticket (number or title)...'))
      .attr('autocomplete', 'off')

    @resultsList = $('<ul>').addClass('kc-bulk-merge-results').css({
      'position': 'absolute'
      'top': '100%'
      'left': '0'
      'right': '0'
      'z-index': '1050'
      'background': '#fff'
      'border': '1px solid #ddd'
      'border-top': 'none'
      'max-height': '200px'
      'overflow-y': 'auto'
      'list-style': 'none'
      'padding': '0'
      'margin': '0'
      'display': 'none'
    })

    @selectedDisplay = $('<span>').addClass('kc-bulk-merge-selected').css({
      'display': 'none'
      'padding': '4px 8px'
      'background': '#e8f4e8'
      'border-radius': '3px'
      'white-space': 'nowrap'
    })

    inputWrap.append(@searchInput)
    inputWrap.append(@resultsList)

    # Merge button
    @mergeButton = $('<div>')
      .addClass('btn btn--primary kc-bulk-merge-submit')
      .text(App.i18n.translateInline('Merge'))
      .css('white-space', 'nowrap')

    container.append(inputWrap)
    container.append(@selectedDisplay)
    container.append(@mergeButton)

    # Insert into the first step
    actionStep = bulkForm.find('.js-action-step')
    actionStep.append(container)

    # Bind events
    @searchInput.on('input.kcBulkMerge', @onSearchInput)
    @searchInput.on('keydown.kcBulkMerge', @onSearchKeydown)
    @mergeButton.on('click.kcBulkMerge', @onMergeSubmit)

    # Close results on outside click
    $(document).on('click.kcBulkMergeOutside', (e) =>
      if !$(e.target).closest('.kc-bulk-merge-search-wrap').length
        @resultsList.hide()
    )

  removeMergeUI: =>
    try
      $('.kc-bulk-merge-ui').remove()
      $(document).off('click.kcBulkMergeOutside')
    catch e
      # silent

  # ---------- Parent ticket search ----------

  onSearchInput: (e) =>
    query = $(e.currentTarget).val()?.trim()
    return @resultsList.hide() if !query || query.length < 2

    @delay(=>
      @searchTickets(query)
    , 300, 'kc-bulk-merge-search')

  onSearchKeydown: (e) =>
    # Escape to close results
    if e.keyCode is 27
      @resultsList.hide()
      return

    # Enter to select first result
    if e.keyCode is 13
      e.preventDefault()
      firstResult = @resultsList.find('li').first()
      if firstResult.length > 0
        firstResult.trigger('click')

  searchTickets: (query) =>
    App.Ajax.request(
      type: 'GET'
      url:  "#{App.Config.get('api_path')}/tickets/search"
      data:
        query: query
        limit: 10
      success: (data, status, xhr) =>
        try
          App.Collection.loadAssets(data.assets) if data.assets
          tickets = []
          if data.tickets
            for ticketId in data.tickets
              ticket = App.Ticket.find(ticketId)
              tickets.push(ticket) if ticket
          @renderSearchResults(tickets)
        catch e
          console.warn '[KC] searchTickets parse failed', e
      error: =>
        @resultsList.hide()
    )

  renderSearchResults: (tickets) =>
    @resultsList.empty()

    if tickets.length is 0
      noResult = $('<li>').css({
        'padding': '8px 12px'
        'color': '#999'
      }).text(App.i18n.translateInline('No tickets found'))
      @resultsList.append(noResult)
      @resultsList.show()
      return

    for ticket in tickets
      do (ticket) =>
        li = $('<li>').css({
          'padding': '8px 12px'
          'cursor': 'pointer'
          'border-bottom': '1px solid #eee'
        }).attr('data-ticket-id', ticket.id)

        li.text("##{ticket.number} - #{ticket.title}")

        li.on('mouseenter', -> $(this).css('background', '#f5f5f5'))
        li.on('mouseleave', -> $(this).css('background', '#fff'))
        li.on('click', =>
          @selectParentTicket(ticket)
        )

        @resultsList.append(li)

    @resultsList.show()

  selectParentTicket: (ticket) =>
    @parentTicketId = ticket.id
    @searchInput.val("##{ticket.number} - #{ticket.title}")
    @selectedDisplay.text("→ ##{ticket.number}").show()
    @resultsList.hide()

  # ---------- Submit ----------

  onMergeSubmit: (e) =>
    try
      e.preventDefault()

      if !@parentTicketId
        App.Event.trigger('notify', {
          type: 'error'
          msg: App.i18n.translateInline('Please select a parent ticket first.')
        })
        return

      # Collect checked ticket IDs
      ticketIds = []
      $('.table [name="bulk"]:checked').each (index, element) ->
        ticketIds.push(parseInt($(element).val(), 10))

      if ticketIds.length is 0
        App.Event.trigger('notify', {
          type: 'error'
          msg: App.i18n.translateInline('At least one ticket must be selected.')
        })
        return

      # Confirm with the user
      count = ticketIds.length
      parentNum = @searchInput.val()
      if !confirm(App.i18n.translateInline('Merge %s ticket(s) into %s?', count, parentNum))
        return

      # Disable button during request
      @mergeButton.addClass('is-disabled').text(App.i18n.translateInline('Merging...'))

      App.Ajax.request(
        type: 'POST'
        url:  "#{App.Config.get('api_path')}/kc/bulk_merge"
        data: JSON.stringify(
          ticket_ids: ticketIds
          parent_ticket_id: @parentTicketId
        )
        processData: false
        contentType: 'application/json'
        success: (data) =>
          App.Event.trigger('notify', {
            type: 'success'
            msg: App.i18n.translateInline('Successfully merged %s ticket(s).', data.merged_count)
          })

          # Uncheck all, reset state, refresh overview
          $('.table [name="bulk"]:checked').prop('checked', false)
          @resetStateDropdown()
          App.Event.trigger('overview:fetch')

        error: (xhr) =>
          try
            errorData = JSON.parse(xhr.responseText)
            msg = errorData.error || App.i18n.translateInline('Merge failed.')
          catch
            msg = App.i18n.translateInline('Merge failed.')

          App.Event.trigger('notify', {
            type: 'error'
            msg: msg
          })

          @mergeButton.removeClass('is-disabled').text(App.i18n.translateInline('Merge'))
      )
    catch e
      console.warn '[KC] onMergeSubmit failed', e
      @mergeButton?.removeClass('is-disabled')?.text(App.i18n.translateInline('Merge'))

  resetStateDropdown: =>
    try
      select = $('#form-ticket-bulk select[name="state_id"]')
      select.val('')
      @exitMergeMode(select)
    catch e
      console.warn '[KC] resetStateDropdown failed', e

App.Config.set('KcBulkMergeHandler', KcBulkMergeHandler, 'Plugins')
