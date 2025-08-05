class App.SidebarTicketSummary extends App.Controller
  DISPLAY_STRUCTURE: [
    { key: 'customer_request', name: __('Customer Intent'), value: 'customer_request' },
    { key: 'conversation_summary', name: __('Conversation Summary'), value: 'conversation_summary' },
    { key: 'open_questions', name: __('Open Questions'), value: 'open_questions', type: 'list' },
    { key: 'upcoming_events', name: __('Upcoming Events'), value: 'upcoming_events', type: 'list' },
    { key: 'customer_sentiment', name: __('Customer Sentiment'), value: ['customer_emotion', 'customer_mood'] },
  ]

  constructor: ->
    super

    @controllerBind('config_update', @configHasChanged)

    return if !@parent?.activeState

    @ticketZoomShown()

  activateSummary: =>
    return if @summaryActivated

    @summaryActivated = true

    @loadSummarization()

    # prepopulate already summarized article IDs
    @summaryReloadNeeded()

    # load new summary if it has changed
    @controllerBind('ticket::summary::update', (data) =>
      return if !@sidebarIsEnabled()
      return if data.ticket_id.toString() isnt @ticket.id.toString()
      return if data.locale isnt App.i18n.get()

      if data.error
        @renderSummarization(error: true)
        return

      if !@isLoadSummaryNow()
        @waitingSummarization = true
        return

      @loadSummarization()
    )

    # check if new summary needs to be requested
    @controllerBind('ui::ticket::load', (data) =>
      return if !@sidebarIsEnabled()
      return if data.ticket_id.toString() isnt @ticket.id.toString()
      return if !@summaryReloadNeeded()
      return if !@isLoadSummaryNow()

      @loadSummarization()
    )

  isLoadSummaryNow: =>
    if @summarizeOnTicketShow()
      !!@parent?.activeState
    else
      @parent?.activeState && @isVisible()

  isVisible: =>
    @parentSidebar?.currentTab == @sidebarItem()?.name

  ticketZoomShown: =>
    return if !@sidebarIsEnabled()

    if @summaryActivated
      if @waitingSummarization && @isLoadSummaryNow()
        @loadSummarization()
      return

    return if !@summarizeOnTicketShow()
    @activateSummary()

  configHasChangedLoadSummary: =>
    return if !@sidebarIsEnabled()

    if !@isLoadSummaryNow()
      @waitingSummarization = true
      return

    @loadSummarization()

  summarizeOnTicketShow: =>
    # Ticket object may have old group contents cached in some cases
    # Load group object directly to make sure it's up to date
    groupSetting = App.Group.find(@ticket.group_id)?.summary_generation

    switch groupSetting
      when 'on_ticket_detail_opening'
        true
      when 'on_ticket_summary_sidebar_activation'
        false
      else
        setting = App.Config.get('ai_assistance_ticket_summary_config') || {}
        setting['generate_on'] != 'on_ticket_summary_sidebar_activation'

  sidebarItem: =>
    return if !@sidebarIsEnabled()

    {
      name:           'summary'
      badgeIcon:      'smart-assist'
      badgeCallback:  @badgeRender
      sidebarHead:     __('Summary')
      sidebarCallback: @sidebarCallback
      sidebarActions:  []
    }

  badgeDetails: =>
    {
      name:       'summary'
      icon:       'smart-assist'
      dotVisible: !@isPreparingData && @fingerprintMD5 && @relevantForCurrentUser && !@constructor.isSummarySeen(@ticket, @fingerprintMD5)
    }

  badgeRender: (el) =>
    @badgeEl = el
    @badgeRenderLocal()

  badgeRenderLocal: =>
    return if !@badgeEl
    @badgeEl.html(App.view('generic/sidebar_tabs_item')(@badgeDetails()))

  shown: =>
    if !@isPreparingData && @fingerprintMD5
      @constructor.markSummaryAsSeen(@ticket, @fingerprintMD5)

    @badgeRenderLocal()

    if @summaryActivated
      if @waitingSummarization && !@summarizeOnTicketShow()
        @loadSummarization()
      return

    @activateSummary()

  sidebarIsEnabled: =>
    return false if !App.Config.get('ai_provider')
    return false if !App.Config.get('ai_assistance_ticket_summary')
    return false if !(@ticket and @ticket.currentView() is 'agent')
    return false if @ticket.state.state_type.name is 'merged'

    true

  sidebarCallback: (el) =>
    @elSidebar = el

  configHasChanged: (config) =>
    switch config.name
      when 'ai_assistance_ticket_summary'
        App.Event.trigger('ui::ticket::sidebarRerender', { taskKey: @taskKey })
      when 'ai_assistance_ticket_summary_config'
        @configHasChangedLoadSummary()

  getAvailableDisplayStructure: ->
    config = App.Config.get('ai_assistance_ticket_summary_config')
    @DISPLAY_STRUCTURE.filter((item) -> !(item.key of config) or config[item.key] is true)

  renderSummarization: (data) =>
    if data
      @summaryData = data

    @updateSummarySeenState(@summaryData)

    return if !@elSidebar

    noSummaryPossible = @summaryData.result && _.every(_.values(@summaryData.result), (item) -> item is null)

    summarization = $(App.view('ticket_zoom/sidebar_ticket_summary')(
      data:              @summaryData
      noSummaryPossible: noSummaryPossible
      structure:         @getAvailableDisplayStructure()
    ))

    summarization
      .on('click', '.js-retry', @retrySummarization)

    @elSidebar.html(summarization)

  retrySummarization: (e) =>
    @preventDefaultAndStopPropagation(e)
    @renderSummarization({})
    @loadSummarization()

  updateSummarySeenState: (data) =>
    @isPreparingData = (_.isNull(data?.result) or data?.error)
    @fingerprintMD5  = data?.result?.fingerprint_md5
    @relevantForCurrentUser = data?.result?.relevant_for_current_user

    App.Event.trigger(
      'ui::ticket::summaryUpdate',
      { ticket_id: @ticket.id, isPreparingData: @isPreparingData, fingerprintMD5: @fingerprintMD5 }
    )

    if @sidebarItem()?.name == @parentSidebar.currentTab && @fingerprintMD5 && !@isPreparingData
      @constructor.markSummaryAsSeen(@ticket, @fingerprintMD5)

    @badgeRenderLocal()

  summaryReloadNeeded: =>
    ticket = App.Ticket.find(@ticket.id)
    ticketSummarizableArticleIds = @getTicketSummarizableArticleIds(ticket.article_ids)

    if @ticketSummarizableArticleIds && _.isEqual(@ticketSummarizableArticleIds, ticketSummarizableArticleIds)
      return false

    @ticketSummarizableArticleIds = ticketSummarizableArticleIds
    true

  getTicketSummarizableArticleIds: (allArticleIds) ->
    allArticleIds.filter (elem) ->
      article = App.TicketArticle.find(elem)
      sender  = App.TicketArticleSender.find(article.sender_id)

      sender.name != 'System' && article.body?.length > 0

  loadSummarization: =>
    return if !@sidebarIsEnabled()
    @waitingSummarization = false

    @ajax(
      id:    "ticket-intelligence-enqueue-#{@taskKey}"
      type:  'POST'
      url:   "#{@apiPath}/tickets/#{@ticket.id}/enqueue_summarize"
      success: (data, status, xhr) =>
        @renderSummarization(data)

      error: (xhr, status, error) ->
        # show error toaster
    )

  @summarySeenLocalStorageKey: (ticket) ->
    "ticket-summary-seen-#{ticket.id}"

  @markSummaryAsSeen: (ticket, fingerprint) =>
    key = @summarySeenLocalStorageKey(ticket)
    App.LocalStorage.set(key, fingerprint)

  @isSummarySeen: (ticket, fingerprint) =>
    key = @summarySeenLocalStorageKey(ticket)

    App.LocalStorage.get(key) is fingerprint


App.Config.set('350-TicketSummary', App.SidebarTicketSummary, 'TicketZoomSidebar')
