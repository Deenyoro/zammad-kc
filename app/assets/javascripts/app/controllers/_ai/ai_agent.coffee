class AIAgent extends App.ControllerAIFeatureBase
  @extend App.PopoverProvidable
  @registerPopovers 'ReferenceList'

  @requiredPermission: 'admin.ai_agent'
  header: __('AI Agents')

  constructor: ->
    super

    App.AIAgentType.fetchFull()

    callbackAgentTypeAttribute = (value, object, attribute, attributes) ->
      return App.i18n.translateContent('||unknown||') if not object.agent_type

      App.AIAgentType.findByAttribute(object.agent_type).displayName()

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

    @genericController = new AIAgentIndex(
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
            agent_type: [ callbackAgentTypeAttribute ]
            triggers: [ callbackTriggersAttribute ]
            jobs: [ callbackJobsAttribute ]
        topAlert: =>
          return if not @missingProvider()

          type: 'warning'
          message: __('The provider configuration is missing. Please set up the provider before proceeding in |AI > Provider|.')
      container: @el.closest('.content')
      handlers: [
        App.FormHandlerAIAgentTypeHelp.run
        App.FormHandlerAIAgentUnusedWarning.run
      ]
      renderCallback: =>
        @renderPopovers()
    )

  show: (params) =>
    for key, value of params
      if key isnt 'el' && key isnt 'shown' && key isnt 'match'
        @[key] = value

    @genericController.paginate(@page || 1, params)

class AIAgentIndex extends App.ControllerGenericIndex
  editControllerClass: -> EditAIAgent
  newControllerClass: -> NewAIAgent

AIAgentModalMixin =
  step: 'initial'
  buttonSubmit: __('Next')
  buttonClass: 'btn--primary'
  headIcon: 'ai-agent'
  headIconClass: 'ai-modal-head-icon'

  # Static fields that are always available
  staticFields: [
    'name'
    'agent_type'
    'note'
    'active'
  ]

  # All possible fields from all steps (static + dynamic)
  allFields: []

  events:
    'click .js-back': 'handleBack'

  # Initialize all fields from all possible steps
  initializeAllFieldsLookup: ->

    # Start with static fields
    @allFields = @staticFields

    # Add fields from all agent type specific steps
    if @agentType?.form_schema
      for schemaItem in @agentType.form_schema
        fieldNames = _.map(schemaItem.fields or [], (field) -> field.name)
        @allFields = @allFields.concat(fieldNames)

  # Set field values from params into target, but only for fields in our field list
  setFormFields: (target, params) ->

    # Early return if no form fields to process
    return target if @allFields.length is 0 || !params

    result = $.extend(true, {}, target)

    # Explicitly set values from params into target, but only for our defined fields
    for fieldName in @allFields
      # Handle nested field paths (e.g., "definition::instruction_context::object_attributes::group_id")
      if fieldName.indexOf('::') > -1
        # Split the field path once
        pathParts = fieldName.split('::')

        # Navigate through params to get the value
        paramsValue = params
        for part in pathParts
          if paramsValue?[part] isnt undefined
            paramsValue = paramsValue[part]
          else
            paramsValue = undefined
            break

        # Only proceed if we found a value
        if paramsValue isnt undefined
          # Navigate/create the nested structure in result
          currentObj = result
          for i in [0...pathParts.length - 1]
            part = pathParts[i]
            if !currentObj[part] or !_.isObject(currentObj[part])
              currentObj[part] = {}
            currentObj = currentObj[part]

          # Set the final value
          finalPart = pathParts[pathParts.length - 1]
          currentObj[finalPart] = paramsValue
      else
        # Simple field, set value from params directly
        if params[fieldName] isnt undefined
          result[fieldName] = params[fieldName]

    result

  maybeSetAgentType: ->
    return if @agentType?.id is @params?.agent_type

    if @params?.agent_type
      @agentType = App.AIAgentType.findByAttribute(@params.agent_type)
    else if @item?.agent_type
      @agentType = App.AIAgentType.findByAttribute(@item.agent_type)

    # Always initialize fields when agent type changes
    @initializeAllFieldsLookup()

  steps: ->
    _.map(@agentType?.form_schema, (item) -> item.step) or []

  firstStep: ->
    @steps()[0]

  lastStep: ->
    @steps()[@steps().length - 1]

  nextStep: ->
    return 'metadata' if not @steps().length or @step is @lastStep()

    @steps()[_.indexOf(@steps(), @step) + 1]

  stepHelp: ->
    _.find(@agentType?.form_schema, (item) -> item.help)?.help or ''

  previousStep: ->
    return 'initial' if not @steps().length or @step is @firstStep()

    @steps()[_.indexOf(@steps(), @step) - 1]

  contentFormParams: ->
    @params = @setFormFields(@item, {}) if _.isEmpty(@params) # init params
    @params

  contentFormModel: ->
    @maybeSetAgentType()

    attrs = $.extend(true, [], App.AIAgent.configure_attributes)

    if @step is 'initial'
      attrs = _.filter(attrs, (attr) -> attr.name is 'name' or attr.name is 'agent_type')

      # Disable `agent_type` field if the item is already persisted.
      if @item?.id
        attribute = attrs.find((attr) -> attr.name is 'agent_type')
        attribute.disabled = true
        attribute.null = true

    else if @step is 'metadata'
      attrs = _.filter(attrs, (attr) -> attr.name is 'note' or attr.name is 'active')

    else
      attrs = _.find(@agentType.form_schema, (item) => item.step is @step)?.fields or []

    { configure_attributes: attrs }

  validateParams: (e) ->
    params = @formParam(e.target)
    newParams = @setFormFields(@params, params)

    @item.load newParams

    # Validate form using HTML5 validity check.
    element = $(e.target).closest('form').get(0)
    if element && element.reportValidity && !element.reportValidity()
      return false

    # Validate object against the form.
    errors = @item.validate(
      controllerForm: @controller
    )

    if @validateOnSubmit
      errors = _.extend({}, errors, @validateOnSubmit(params))

    if !_.isEmpty(errors)
      @log 'error', errors
      @formValidate( form: e.target, errors: errors )
      return false

    @params = newParams

    @maybeSetAgentType()

    true

  renderStep: (e) ->
    @update()

    return if @step is 'initial' or @step is 'metadata' or not helpText = @stepHelp()

    $('<p />').addClass('text-muted')
      .html(App.i18n.translateContent(helpText))
      .prependTo(@controller.form)

  handleBack: (e) ->
    return false if @step is 'initial'

    e.stopPropagation()
    e.preventDefault()

    return if not @validateParams(e)

    if @step is 'metadata' and @steps().length
      @step = @lastStep()
      @buttonSubmit = __('Next')
      @buttonClass = 'btn--primary'

    else
      @step = @previousStep()

      if @step is 'initial'
        @buttonSubmit = __('Next')
        @buttonClass = 'btn--primary'
        @buttonCancel = __('Cancel & Go Back')
        @leftButtons = []

    @renderStep(e)

    true

  handleNext: (e) ->
    return false if @step is 'metadata'

    return if not @validateParams(e)

    if @step is 'initial' and @steps().length
      @step = @firstStep()
      @buttonCancel = false
      @leftButtons = [
        {
          text: __('Back')
          className: 'js-back'
        }
      ]

    else
      @step = @nextStep()

      if @step is 'metadata'
        @buttonSubmit = __('Submit')
        @buttonClass = 'btn--success'
        @buttonCancel = false
        @leftButtons = [
          {
            text: __('Back')
            className: 'js-back'
          }
        ]

    @renderStep(e)

    true

class EditAIAgent extends App.ControllerGenericEdit
  @include AIAgentModalMixin

  constructor: ->
    super

    @initializeAllFieldsLookup()

  onSubmit: (e) =>
    return if @handleNext(e)

    # Load the current params into the item.
    #   Super method will only know about the current step params.
    @item.load(@params)

    # Step is `metadata`, call the super method to save the item.
    super

class NewAIAgent extends App.ControllerGenericNew
  @include AIAgentModalMixin

  constructor: ->
    super

    @item = new App[ @genericObject ]

    @initializeAllFieldsLookup()

  onSubmit: (e) =>
    return if @handleNext(e)

    params = @formParam(e.target)
    newParams = @setFormFields(@params, params)

    @item.load(newParams)

    # Validate form using HTML5 validity check.
    element = $(e.target).closest('form').get(0)
    if element && element.reportValidity && !element.reportValidity()
      return false

    # Validate object against the form.
    errors = @item.validate(
      controllerForm: @controller
    )

    if @validateOnSubmit
      errors = _.extend({}, errors, @validateOnSubmit(params))

    if !_.isEmpty(errors)
      @log 'error', errors
      @formValidate( form: e.target, errors: errors )
      return false

    # Disable form.
    @formDisable(e)

    # Save object.
    ui = @
    @item.save(
      done: ->
        if ui.callback
          item = App[ ui.genericObject ].fullLocal(@id)
          ui.callback(item)
        ui.close()

      fail: (settings, details) =>
        ui.log 'errors', details
        ui.formEnable(e)

        if details && details.invalid_attribute
          @formValidate( form: e.target, errors: details.invalid_attribute )
        else
          ui.controller.showAlert(details.error_human || details.error || __('The object could not be created.'))
    )

App.Config.set('AIAgents', { prio: 1300, name: __('AI Agents'), parent: '#ai', target: '#ai/ai_agents', controller: AIAgent, permission: ['admin.ai_agent'] }, 'NavBarAdmin')
