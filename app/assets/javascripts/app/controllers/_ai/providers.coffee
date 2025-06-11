class AiProviders extends App.Controller
  @requiredPermission: 'admin.ai'
  title: __('Provider')
  description: __('This service allows you to connect Zammad with an AI provider.')

  constructor: ->
    if @constructor.requiredPermission
      @permissionCheckRedirect(@constructor.requiredPermission)

    super

    App.Setting.fetchFull(
      @render
      force: false
    )

  render: =>
    @html App.view('ai/providers')(
      title: @title,
      description: @description,
    )
    new ProviderForm()

class ProviderForm extends App.Controller
  events:
    '.js-provider-submit': 'update'

  constructor: (content) ->
    super

    @providers = @activeProviders()

    @render(content)


  activeProviders: ->
    allProviders = App.Config.get('AIProviders')

    Object.entries(allProviders)
      .filter(([_, provider]) ->
        if typeof provider.active is 'function'
          provider.active()
        else
          provider.active
      )
      .reduce((acc, [key, provider]) ->
        acc[key] = provider
        acc
      , {})

  getProviderOptions: ->
    Object
      .entries(@providers)
      .sort(([_, a], [__, b]) -> a.prio - b.prio)
      .reduce((acc, [key, { label }]) ->
        acc[key] = label
        acc
      , {})

  getInputFields: (provider, params) ->
    {
      token: {
        name: 'token',
        display: __('Token'),
        tag: 'input',
        type: 'password',
        null: false,
        single: true,
        required: 'true',
        autocomplete: 'off',
        value: params.token,
      }
      model: {
        name: 'model',
        display: __('Model'),
        tag: 'input',
        type: 'text',
        null: true,
        single: true,
        placeholder: provider.default_model,
        autocomplete: 'off',
        value: params.model,
      }
      url: {
        name: 'url',
        display: __('URL'),
        tag: 'input',
        type: 'text',
        null: false,
        autocomplete: 'off',
        value: params.url,
        placeholder: 'http://localhost:11434'
      }
      url_completions: {
        name: 'url_completions',
        display: __('URL (Completions)'),
        tag: 'input',
        type: 'text',
        null: false,
        autocomplete: 'off',
        value: params.url_completions,
        placeholder: ''
      }
      url_embeddings: {
        name: 'url_embeddings',
        display: __('URL (Embeddings)'),
        tag: 'input',
        type: 'text',
        null: false,
        autocomplete: 'off',
        value: params.url_embeddings,
        placeholder: ''
      }
    }


  providerConfiguration: (provider, params) ->
    if not @providers[provider]
      provider = ''

    result = [
      {
        name: 'provider'
        display: __('Provider')
        tag: 'select'
        options: @getProviderOptions()
        null: true
        nulloption: true
        value: provider
        customsort: 'on'
      },
    ]

    currentProvider = @providers[provider]

    return result if !currentProvider

    providerParams = if App.Setting.get('ai_provider') == provider then params else {}
    fields         = @getInputFields(currentProvider, providerParams)

    result.concat _.map(currentProvider.fields, (field) -> fields[field])

  render: (provider) ->
    config = App.Setting.get('ai_provider_config') || {}
    current_provider = if provider != undefined then provider else App.Setting.get('ai_provider')

    configure_attributes = @providerConfiguration(current_provider, config)

    @providerSettingsForm?.releaseController()
    @providerSettingsForm = new App.ControllerForm(
      el:        $('.js-form'),
      model:     { configure_attributes: configure_attributes },
      autofocus: true,
      fullForm: true,
      fullFormSubmitLabel: 'Save',
      fullFormSubmitAdditionalClasses: 'btn--primary js-provider-submit',
    )

    $('.js-provider-submit').on('click', @update)
    $('select[name=provider]').on('change', (e) =>
      @render($(e.target).val()))



  update: (e) =>
    e.preventDefault()

    params = @formParam(e.target)

    selectedProvider = @providers[params.provider]

    if selectedProvider?.key
      params.provider = selectedProvider.key
    else
      params = {}

    params = @formParam(e.target)

    errors = @providerSettingsForm.validate(params)

    # show errors in form
    if errors
      @log 'error', errors
      @formValidate(form: e.target, errors: errors)
      return

    @validateAndSave(params)

  validateAndSave: (params) ->
    provider = params.provider

    delete params.provider
    if !params.model || params.model.trim() == ''
      delete params.model

    config = params

    App.Setting.set('ai_provider', provider, done: -> App.Setting.set('ai_provider_config', config, notify: true))

App.Config.set('Provider', { prio: 1000, name: __('Provider'), parent: '#ai', target: '#ai/provider', controller: AiProviders, permission: ['admin.ai'] }, 'NavBarAdmin')
