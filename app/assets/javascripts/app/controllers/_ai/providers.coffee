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
    providers = Object.entries(@providers).sort(([_, a], [__, b]) -> a.order - b.order)
    providers.reduce((acc, [key, { label }]) ->
      acc[key] = label
      acc
    , {})

  getInputFields: (params) ->
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
    }


  providerConfiguration: (provider, params) ->
    if not @providers[provider]
      provider = ''

    result = [
      {
        name: 'provider',
        display: __('Provider'),
        tag: 'select',
        options: @getProviderOptions(),
        null: true,
        nulloption: true,
        value: provider
      },
    ]

    currentProvider = @providers[provider]

    if(currentProvider)
      fields = @getInputFields(if App.Setting.get('ai_provider') == provider then params else {})

      fieldsConfig = []

      for field in currentProvider.fields
        fieldsConfig.push(fields[field])

      result = result.concat(fieldsConfig)

    result

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
    config = params

    App.Setting.set('ai_provider', provider, done: -> App.Setting.set('ai_provider_config', config, notify: true))


App.Config.set('Provider', { prio: 1000, name: __('Provider'), parent: '#ai', target: '#ai/provider', controller: AiProviders, permission: ['admin.ai'] }, 'NavBarAdmin')
