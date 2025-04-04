class SidebarTicketSummary extends App.Controller
  DISPLAY_STRUCTURE: [
    { key: 'problem', name: __('Customer Intent'), value: 'problem' },
    { key: 'conversation_summary', name: __('Conversation Summary'), value: 'conversation_summary' },
    { key: 'open_questions', name: __('Open Questions'), value: 'open_questions', type: 'list' },
    { key: 'suggestions', name: __('Suggested Next Steps'), value: 'suggestions', type: 'list' },
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

  showSummarization: (payload) =>
    noSummaryPossible = payload?.data?.result && Object.values(payload.data.result).every((item) -> item == null)

    summarization = $(App.view('ticket_zoom/sidebar_ticket_summary')(
      data:      payload?.data,
      noSummaryPossible: noSummaryPossible
      structure: @getAvailableDisplayStructure()
    ))
    @elSidebar.html(summarization)
    @elSidebar.find('.js-retry').on('click', @retrySummarization)

  retrySummarization: (e) =>
    @preventDefaultAndStopPropagation(e)

    @showSummarization({})
    @parent.triggerArticleSummaryUpdate()


App.Config.set('350-TicketSummary', SidebarTicketSummary, 'TicketZoomSidebar')
