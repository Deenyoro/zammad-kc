class ProfileAppearance extends App.ControllerSubContent
  @requiredPermission: 'user_preferences.appearance'
  header: __('Appearance')
  elements:
    'input[name="summary_banner_visible"]': 'summaryBannerCheckbox'
  events:
    'change input[name="theme"]': 'updateTheme'
    'change input[name="summary_banner_visible"]': 'saveSummaryBannerVisibility'

  constructor: ->
    super
    @render()
    @controllerBind('ui:theme:saved', @render)
    @listenTo App.User.current(), 'refresh', @bannerVisibilityMayHaveChanged
    @controllerBind('config_update', @configUpdate)

  render: (params) =>
    @html App.view('profile/appearance')(
      theme: params?.theme || App.Session.get('preferences').theme || 'auto'
      isSummaryBannerVisible: @isSummaryBannerVisible()
      isProviderConfigured: App.Config.get('ai_provider')
      isAgent: @permissionCheck('ticket.agent')
    )

  updateTheme: (event) ->
    @preventDefaultAndStopPropagation(event)
    App.Event.trigger('ui:theme:set', { theme: event.target.value, save: true })

  bannerVisibilityMayHaveChanged: =>
    @summaryBannerCheckbox.prop('checked', @isSummaryBannerVisible())

  saveSummaryBannerVisibility: =>
    @summaryBannerCheckbox.prop('disabled', true)

    value = !@summaryBannerCheckbox.prop('checked')

    @ajax(
      id:          'preferences'
      type:        'PUT'
      url:         "#{@apiPath}/users/preferences"
      data:        JSON.stringify(ticket_summary_banner_hidden: value)
      processData: true
      success: =>
        @summaryBannerCheckbox.prop('disabled', false)
      error: =>
        @summaryBannerCheckbox.prop('checked', !value)
        @summaryBannerCheckbox.prop('disabled', false)
    )

  configUpdate: (config) =>
    if config?.name is 'ai_provider' then @render()

  isSummaryBannerVisible: ->
    !App.User.current()?.preferences?.ticket_summary_banner_hidden and App.Config?.get('ai_provider')

App.Config.set('Appearance', { prio: 900, name: __('Appearance'), parent: '#profile', target: '#profile/appearance', controller: ProfileAppearance, permission: ['user_preferences.appearance'] }, 'NavBarProfile')
