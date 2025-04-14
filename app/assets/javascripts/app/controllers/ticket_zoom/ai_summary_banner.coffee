class App.TicketZoomAiSummaryBanner extends App.Controller
  constructor: ->
    super

    @localStorageKey = "#{@object_id}-ticket-summary-banner-seen"

    @html App.view('ticket_zoom/ai_summary_banner')(
      isPreparingData: @isPreparingData
    )

    @bannerVisibilityMayHaveChanged()

    @listenTo App.User.current(), 'refresh', @bannerVisibilityMayHaveChanged

    @controllerBind('ui::ticket::summarySidebar::shown', (payload) =>
      return if payload.ticket_id isnt @object_id
      return if not @isBannerVisible()

      @hideOnSeen()
    )

    @controllerBind('ui::ticket::summaryUpdate', (payload) =>
      return if payload.ticket_id isnt @object_id

      @isPreparingData = _.isNull(payload.data?.result) or payload.data?.error
      @fingerprintMD5  = payload.data?.result?.fingerprint_md5

      @toggleMessages()
      @bannerVisibilityMayHaveChanged()
    )

  events:
    'click .js-hide-banner': 'hideBanner'
    'click .js-see-summary': 'seeSummary'

  bannerVisibilityMayHaveChanged: =>
    @el.toggle(@isBannerVisible())

  hideBanner: (e) =>
    @preventDefaultAndStopPropagation(e)

    new App.ControllerConfirm(
      head:  __('Hide Smart Assist Summary Banner?')
      message: __('You can re-enable it anytime in Profile Settings > Appearance.')
      buttonSubmit: __('Yes, hide it')
      callback: @doHide
    )

  doHide: =>
    @el.hide()

    @ajax(
      id:          'preferences'
      type:        'PUT'
      url:         "#{@apiPath}/users/preferences"
      data:        JSON.stringify(ticket_summary_banner_hidden: true)
      processData: true
    )

  seeSummary: (e) =>
    @preventDefaultAndStopPropagation(e)

    # If the summary tab is already active, explicitly hide the banner and remember the fingerprint.
    if @el.closest('.content').find(".tabsSidebar-tab.active[data-tab='summary']").length
      @hideOnSeen()
      return

    # Otherwise, activate the summary tab and leave hiding to the `shown` event handler.
    @el
      .closest('.content')
      .find(".tabsSidebar-tab[data-tab='summary']:not(.active)")
      .click()

  isBannerVisible: =>
    not App.User.current()?.preferences?.ticket_summary_banner_hidden and App.LocalStorage.get(@localStorageKey) isnt @fingerprintMD5

  hideOnSeen: =>
    @el.hide()

    # Do not remember hiding of the banner if the data is still being prepared or the fingerprint is missing.
    return if @isPreparingData or not @fingerprintMD5

    App.LocalStorage.set(@localStorageKey, @fingerprintMD5)

  toggleMessages: =>
    if @isPreparingData
      @el.find('.js-message-preparing').show()
      @el.find('.js-message-generated').hide()

      return

    @el.find('.js-message-preparing').hide()
    @el.find('.js-message-generated').show()
