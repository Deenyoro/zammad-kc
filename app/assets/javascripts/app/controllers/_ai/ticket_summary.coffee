class App.TicketSummary extends App.ControllerAIFeatureBase
  header: __('Ticket Summary')
  description: __('%s provides the functionality to summarize the current ticket state. It will provide a new sidebar which contains information to reduce reading time in the ticket with a summarized version of the problem, open questions and suggestions.')
  requiredPermission: 'admin.ai_assistance_ticket_summary'
  events:
    'change .js-aiAssistanceTicketSummarySetting input': 'toggleAIAssistanceTicketSummarySetting'
    'change .checkbox--service input': 'toggleService'
    'submit .js-ticketSummaryGenerationConfig': 'selectGenerationConfig'

  elements:
    '.js-aiAssistanceTicketSummarySetting input': 'aiAssistanceTicketSummarySetting'
    '.js-missingProviderAlert': 'missingProviderAlert'

  constructor: ->
    super

    @controllerBind('config_update', (data) =>
      if data.name == 'ai_assistance_ticket_summary' or data.name == 'ai_provider'
        @missingProviderAlert.toggleClass('hide', !@showAlert())
        @aiAssistanceTicketSummarySetting.prop('checked', App.Config.get('ai_assistance_ticket_summary'))
      else if data.name == 'ai_assistance_ticket_summary_config'
        for key, value of data.value
          field = @$("[name='#{key}']")

          if field.is('select')
            field.val(value)
          else
            field.prop('checked', value)
    )

  showAlert: =>
    App.Config.get('ai_assistance_ticket_summary') && @missingProvider()

  render: =>
    service_config = App.Setting.get('ai_assistance_ticket_summary_config') || {}

    @html App.view('ai/ticket_summary')(
      description: marked(App.i18n.translateContent(@description, '**Zammad Smart Assist**'))
      serviceOptions: @serviceOptions(service_config)
      generationOptions: @generationOptions(service_config['generate_on'])
      missingProvider: @missingProvider()
    )

  serviceOptions: (config) ->
    [
      {
        name: __('Customer Intent')
        key: 'problem'
        description: __('Provide a summary of the problem the customer needs to get resolved.')
        active: true,
        disabled: true,
      },
      {
        name: __('Conversation Summary')
        key: 'conversation_summary'
        description: __('Provide a summary of the conversation between customer and support agent.')
        active: true,
        disabled: true,
      },
      {
        name: __('Open Questions')
        key: 'open_questions'
        description: __('Provide a summary of the questions raised in the conversation.')
        active: config.open_questions,
      }
      {
        name: __('Suggested Next Steps')
        flags: ['experimental']
        key: 'suggestions'
        description: __('Provide some possible solutions to the problem as follow-up items.')
        active: config.suggestions,
      }
    ]

  toggleAIAssistanceTicketSummarySetting:  =>
    value = @aiAssistanceTicketSummarySetting.prop('checked')
    App.Setting.set('ai_assistance_ticket_summary', value, failLocal: @failLocal, doneLocal: @doneLocal, notify: true)

  toggleService: (e) ->
    value = $(e.currentTarget).prop('checked')
    key = $(e.currentTarget).attr('name')

    config = App.Setting.get('ai_assistance_ticket_summary_config') || {}
    config[key] = value
    App.Setting.set('ai_assistance_ticket_summary_config', config, failLocal: @failLocal, notify: true)

  generationOptions: (selectedConfigName) ->
    [
      {
        label: __('On ticket detail opening')
        value: 'on_ticket_detail_opening'
        selected: selectedConfigName == 'on_ticket_detail_opening'
      },
      {
        label: __('On ticket summary sidebar activation')
        value: 'on_ticket_summary_sidebar_activation'
        selected: selectedConfigName == 'on_ticket_summary_sidebar_activation'
      }
    ]

  selectGenerationConfig: (e) ->
    e.preventDefault()
    value = $(e.currentTarget).find('[name="generate_on"]').val()

    config = App.Setting.get('ai_assistance_ticket_summary_config') || {}
    config['generate_on'] = value

    App.Setting.set('ai_assistance_ticket_summary_config', config, failLocal: @failLocal, notify: true)

  doneLocal: =>
    @missingProviderAlert.toggleClass('hide', !@showAlert())

  failLocal: =>
    @render()

App.Config.set('Summary', { prio: 1200, name: __('Ticket Summary'), parent: '#ai', target: '#ai/ticket_summary', controller: App.TicketSummary, permission: ['admin.ai_assistance_ticket_summary'] }, 'NavBarAdmin')
