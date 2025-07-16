class App.ControllerAIFeatureBase extends App.Controller
  constructor: ->
    if @constructor.requiredPermission
      @permissionCheckRedirect(@constructor.requiredPermission)

    super

    App.Setting.fetchFull(
      @render
      force: false
    )

  missingProvider: ->
    _.isEmpty(App.Config.get('ai_provider'))

