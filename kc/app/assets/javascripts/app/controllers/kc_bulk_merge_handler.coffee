# KC: Bulk merge from ticket overview.
#
# This controller:
#   1. Injects a "Merge" button next to "Confirmation" in the bulk action bar
#   2. When clicked, transitions to a merge step with parent ticket search
#   3. On submit, calls POST /api/v1/kc/bulk_merge
#   4. Only shows when kc_bulk_merge setting is enabled
#
# Registered as a Plugin so it auto-initializes with the application.
#
# HARDENING:
#   - All DOM manipulation wrapped in try/catch
#   - MutationObserver with debounce for re-injection on DOM changes
#   - Safe DOM element construction (no raw HTML string concatenation)
class KcBulkMergeHandler extends App.Controller
  constructor: ->
    super
    try
      @parentTicketId = null

      # Watch for DOM changes (bulk form is rendered dynamically)
      @startObserver()

      # Inject into any existing bulk forms
      @injectAll()
    catch e
      console.warn '[KC] KcBulkMergeHandler init failed', e

  release: =>
    try
      @parentTicketId = null
      $(document).off('.kcBulkMerge')
      @stopObserver()
    catch e
      console.warn '[KC] KcBulkMergeHandler release failed', e

  # ---------- DOM injection ----------

  injectAll: =>
    try
      return if !App.Setting.get('kc_bulk_merge')

      # Find all bulk action forms and inject a Merge button next to Confirmation
      $('.bulkAction-form .js-action-step').each (i, actionStep) =>
        @injectMergeButton($(actionStep))
    catch e
      console.warn '[KC] injectAll (merge) failed', e

  injectMergeButton: (actionStep) =>
    return if !actionStep || actionStep.length is 0
    # Skip if already injected
    return if actionStep.find('.kc-bulk-merge-btn').length > 0

    confirmBtn = actionStep.find('.js-confirm')
    return if confirmBtn.length is 0

    mergeBtn = $('<div>')
      .addClass('btn btn--primary kc-bulk-merge-btn')
      .text(App.i18n.translateInline('Merge'))
      .css('white-space', 'nowrap')
      .on('click.kcBulkMerge', @onMergeBtnClick)

    confirmBtn.after(mergeBtn)

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

  # ---------- Merge button click — transition to merge step ----------

  onMergeBtnClick: (e) =>
    try
      e.preventDefault()
      e.stopPropagation()

      bulkForm = $(e.currentTarget).closest('.bulkAction-form')
      return if bulkForm.length is 0

      @parentTicketId = null

      # Hide the normal action step and confirm step
      bulkForm.find('.js-action-step').addClass('hide')
      bulkForm.find('.js-confirm-step').addClass('hide')

      # Remove any previous merge step
      bulkForm.find('.kc-bulk-merge-step').remove()

      # Build and show the merge step
      @buildMergeStep(bulkForm)
    catch e
      console.warn '[KC] onMergeBtnClick failed', e

  buildMergeStep: (bulkForm) =>
    step = $('<div>').addClass('kc-bulk-merge-step').css({
      'display': 'flex'
      'align-items': 'center'
      'gap': '10px'
      'padding': '10px'
    })

    # Parent ticket search input + results dropdown
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
      'bottom': '100%'
      'left': '0'
      'right': '0'
      'z-index': '1050'
      'background': '#fff'
      'border': '1px solid #ddd'
      'border-bottom': 'none'
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

    # Action buttons
    cancelBtn = $('<a>')
      .addClass('btn btn--text btn--secondary kc-bulk-merge-cancel')
      .text(App.i18n.translateInline('Go Back'))
      .on('click.kcBulkMerge', (e) => @onMergeCancel(e, bulkForm))

    @mergeSubmitBtn = $('<div>')
      .addClass('btn btn--primary kc-bulk-merge-submit')
      .text(App.i18n.translateInline('Merge'))
      .css('white-space', 'nowrap')
      .on('click.kcBulkMerge', @onMergeSubmit)

    step.append(inputWrap)
    step.append(@selectedDisplay)
    step.append(cancelBtn)
    step.append(@mergeSubmitBtn)

    bulkForm.append(step)

    # Prevent Enter in the merge step from triggering the parent form's submit
    step.on('keydown.kcBulkMerge', (e) ->
      if e.keyCode is 13
        e.preventDefault()
    )

    # Focus the search input
    setTimeout((=> @searchInput.trigger('focus')), 50)

    # Bind events
    @searchInput.on('input.kcBulkMerge', @onSearchInput)
    @searchInput.on('keydown.kcBulkMerge', @onSearchKeydown)

    # Close results on outside click
    $(document).on('click.kcBulkMergeOutside', (e) =>
      if !$(e.target).closest('.kc-bulk-merge-search-wrap').length
        @resultsList?.hide()
    )

  onMergeCancel: (e, bulkForm) =>
    try
      e.preventDefault()
      @parentTicketId = null

      # Remove merge step, restore action step
      bulkForm.find('.kc-bulk-merge-step').remove()
      bulkForm.find('.js-action-step').removeClass('hide')
      $(document).off('click.kcBulkMergeOutside')
    catch e
      console.warn '[KC] onMergeCancel failed', e

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
      firstResult = @resultsList.find('li[data-ticket-id]').first()
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
    @selectedDisplay.text("\u2192 ##{ticket.number}").show()
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
      @mergeSubmitBtn.addClass('is-disabled').text(App.i18n.translateInline('Merging...'))

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

          # Uncheck all (trigger change so bulk form's show/hide logic fires),
          # hide bulk bar, refresh overview
          $('.table [name="bulk"]:checked').prop('checked', false).first().trigger('change')
          @closeMergeStep()
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

          @mergeSubmitBtn.removeClass('is-disabled').text(App.i18n.translateInline('Merge'))
      )
    catch e
      console.warn '[KC] onMergeSubmit failed', e
      @mergeSubmitBtn?.removeClass('is-disabled')?.text(App.i18n.translateInline('Merge'))

  closeMergeStep: =>
    try
      @parentTicketId = null
      mergeStep = $('.kc-bulk-merge-step')
      if mergeStep.length > 0
        bulkAction = mergeStep.closest('.bulkAction')
        bulkForm = mergeStep.closest('.bulkAction-form')
        mergeStep.remove()
        bulkForm.find('.js-action-step').removeClass('hide')

        # Hide the bulk action bar (must reference before .remove() detaches the element)
        bulkAction.addClass('hide')
      $(document).off('click.kcBulkMergeOutside')
    catch e
      console.warn '[KC] closeMergeStep failed', e

App.Config.set('KcBulkMergeHandler', KcBulkMergeHandler, 'Plugins')
