class CollectionAssets extends App.Controller
  constructor: ->
    super

    return if !@authenticateCheck()

    App.Role.subscribe(->)
    App.Group.subscribe(->)
    App.TicketState.subscribe(->)
    App.TicketPriority.subscribe(->)
    App.ChecklistTemplate.subscribe(->)

App.Config.set('collection_assets', CollectionAssets, 'Plugins')
