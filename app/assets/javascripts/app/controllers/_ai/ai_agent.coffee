class AIAgent extends App.ControllerAIFeatureBase
  @extend App.PopoverProvidable
  @registerPopovers 'ReferenceList'

  @requiredPermission: 'admin.ai_agent'
  header: __('AI Agents')

  constructor: ->
    super

    callbackTypeAttribute = (value, object, attribute, attributes) ->
      App.i18n.translateInline('Ticket Group Dispatcher') # TODO

    callbackReferenceAttribute = (object, attribute, key, title, translationMultiple) ->
      return '-' if _.isEmpty(object.references?[key])

      attribute.class = 'reference-list-popover'
      attribute.data =
        type: key
        title: title
        ids: _.map(object.references[key] || [], (obj) -> obj.id)

      return App.i18n.translateInline(translationMultiple, object.references[key].length) if object.references[key].length > 1

      object.references[key][0].name

    callbackTriggersAttribute = (value, object, attribute, attributes) ->
      callbackReferenceAttribute object, attribute, 'Trigger', __('AI agent used in triggers'), __('%s triggers')

    callbackJobsAttribute = (value, object, attribute, attributes) ->
      callbackReferenceAttribute object, attribute, 'Job', __('AI agent used in schedulers'), __('%s schedulers')

    @genericController = new App.ControllerGenericIndex(
      el: @el
      id: @id
      genericObject: 'AIAgent'
      defaultSortBy: 'name'
      searchBar: true
      searchQuery: @search_query
      pageData:
        home: 'ai_agents'
        object: __('AI Agent')
        objects: __('AI Agents')
        searchPlaceholder: __('Search for AI agents')
        pagerAjax: true
        pagerBaseUrl: '#ai/ai_agents/'
        pagerSelected: ( @page || 1 )
        pagerPerPage: 50
        navupdate: '#ai/ai_agents'
        buttons: [
          { name: __('New AI Agent'), 'data-type': 'new', class: 'btn--success' }
        ]
        tableExtend:
          callbackAttributes:
            type: [ callbackTypeAttribute ]
            triggers: [ callbackTriggersAttribute ]
            jobs: [ callbackJobsAttribute ]
        topAlert: =>
          return if not @missingProvider()

          type: 'warning'
          message: __('The provider configuration is missing. Please set up the provider before proceeding in |AI > Provider|.')
      container: @el.closest('.content')
      renderCallback: =>
        @renderPopovers()
    )

  show: (params) =>
    for key, value of params
      if key isnt 'el' && key isnt 'shown' && key isnt 'match'
        @[key] = value

    @genericController.paginate(@page || 1, params)

App.Config.set('AIAgents', { prio: 1300, name: __('AI Agents'), parent: '#ai', target: '#ai/ai_agents', controller: AIAgent, permission: ['admin.ai_agent'] }, 'NavBarAdmin')
