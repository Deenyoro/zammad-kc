class SidebarTicketSummary extends App.Controller
  DISPLAY_STRUCTURE: [
    { key: 'problem', name: __('Customer Intent'), value: 'problem' },
    { key: 'conversation_summary', name: __('Conversation Summary'), value: 'conversation_summary' },
    { key: 'open_questions', name: __('Open Questions'), value: 'open_questions', type: 'list' },
    { key: 'suggestions', name: __('Suggested Next Steps'), value: 'suggestions', feature: 'checklist', type: 'list' },
  ]

  constructor: ->
    super

    @controllerBind('ui::ticket::summaryUpdate', @summaryLoaded)
    @controllerBind('config_update', @configUpdate)

  configUpdate: (config) =>
    if config.name is 'ai_assistance_ticket_summary_config'
      @parent.triggerArticleSummaryUpdate()

  summaryLoaded: (payload) =>
    return if !@elSidebar
    return if payload.ticket_id isnt @ticket.id

    @showSummarization(payload)

  getAvailableDisplayStructure: ->
    config = App.Config.get('ai_assistance_ticket_summary_config')

    if not App.Config.get('checklist')
      @DISPLAY_STRUCTURE.find((item) -> item.key is 'suggestions').feature = undefined

    @DISPLAY_STRUCTURE.filter((item) -> !(item.key of config) or config[item.key] is true)

  sidebarItem: =>
    return if !App.Config.get('ai_assistance_ticket_summary')
    return if !(@ticket and @ticket.currentView() is 'agent')
    return if @ticket.state.state_type.name is 'merged'

    @item = {
      name:           'summary'
      badgeIcon:      'smart-assist'
      sidebarHead:     __('Summary')
      sidebarCallback: @sidebarCallback
      sidebarActions:  []
    }

    @item

  shown: =>
    @showSummarization(@parent.ticketSummaryData)

  sidebarCallback: (el) =>
    @elSidebar = el

  createChecklist: (callback) =>
    @ajax(
      id:   'checklist_ticket_create_empty'
      type: 'POST'
      url:  "#{@apiPath}/checklists"
      data: JSON.stringify({ ticket_id: @ticket.id })
      processData: true
      success: callback
      error: =>
        @notify(
          type: 'error'
          msg: App.i18n.translateInline('Unable to create checklist.')
        )
    )

  convertToChecklistItem: (event) =>
    target = $(event.target).closest('.js-btn-add-checklist-item')
    return if !target

    text = $(target).data('content')
    checklistId = @ticket.checklist_id

    if !checklistId
      @createChecklist((data) =>
        @ticket.checklist_id = data.id
        @createChecklistItem(data.id, text)
      )
    else
      @createChecklistItem(checklistId, text)

  createChecklistItem: (checklistId, text) =>
    item = new App.ChecklistItem
    item.checklist_id = checklistId
    item.text = text

    item.save(
      done: =>
        @notify(
          type: 'success'
          msg: App.i18n.translateInline('Checklist item successfully added.')
        )
      fail: =>
        @notify(
          type: 'error'
          msg: App.i18n.translateInline('Unable to add checklist item.')
        )
    )

  convertAllToChecklistItems: =>
    checklistId = @ticket.checklist_id

    itemData = _.map(@summaryItems.suggestions, (text) ->
      text: text
      checked: false
    )

    if !checklistId
      checklist = new App.Checklist
      checklist = @createChecklist((data) =>
        @ticket.checklist_id = data.id
        @createBulkChecklistItems(data.id, itemData)
      )
    else
      @createBulkChecklistItems(checklistId, itemData)

  openChecklist: =>
    @elSidebar
      .closest('.content')
      .find(".tabsSidebar-tab[data-tab='checklist']:not(.active)")
      .click()

  createBulkChecklistItems: (checklistId, items) =>
    @ajax(
      id:   'checklist_ticket_create_bulk'
      type: 'POST'
      url:  "#{@apiPath}/checklist_items/create_bulk"
      processData: true
      data: JSON.stringify(
        checklist_id: checklistId
        items: items
      )
      success:  =>
        @openChecklist()
      error: =>
        @notify(
          type: 'error'
          msg: App.i18n.translateInline('Unable to add all checklist items.')
        )
    )

  showSummarization: (payload) =>
    return if not payload?.data

    @summaryItems = payload.data.result

    noSummaryPossible = @summaryItems and _.every(_.values(@summaryItems), (item) -> item is null)

    summarization = $(App.view('ticket_zoom/sidebar_ticket_summary')(
      data:              payload.data,
      noSummaryPossible: noSummaryPossible
      structure:         @getAvailableDisplayStructure()
    ))

    @elSidebar.html(summarization)

    @elSidebar.find('.js-retry').off('click.retry').on('click.retry', @retrySummarization)
    @elSidebar.find('.js-btn-add-checklist-item').off('click.convert').on('click.convert', @convertToChecklistItem)
    @elSidebar.find('.js-btn-ticket-summary-add-all-to-checklist').off('click.convert_all').on('click.convert_all', @convertAllToChecklistItems)

  retrySummarization: (e) =>
    @preventDefaultAndStopPropagation(e)

    @showSummarization({})
    @parent.triggerArticleSummaryUpdate()


App.Config.set('350-TicketSummary', SidebarTicketSummary, 'TicketZoomSidebar')
