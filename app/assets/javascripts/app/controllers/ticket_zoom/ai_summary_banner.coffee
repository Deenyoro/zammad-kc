class App.TicketZoomAiSummaryBanner extends App.Controller
  constructor: ->
    super
    @html App.view('ticket_zoom/ai_summary_banner')()

    if !@isBannerVisible()
      @el.hide()

    @listenTo App.User.current(), 'refresh', @bannerVisibilityMayHaveChanged

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

    @el
      .closest('.content')
      .find(".tabsSidebar-tab[data-tab='summary']:not(.active)")
      .click()

  isBannerVisible: ->
    !App.User.current()?.preferences?.ticket_summary_banner_hidden
