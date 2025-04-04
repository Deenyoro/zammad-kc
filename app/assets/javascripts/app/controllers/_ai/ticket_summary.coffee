class App.TicketSummary extends App.ControllerAIFeatureBase
  header: __('Ticket Summary')
  description: __('%s provides the functionality to summarize the current ticket state. It will provide a new sidebar which contains information to reduce reading time in the ticket with a summarized version of the problem, open questions and suggestions.')
  requiredPermission: 'admin.ai_assistance_ticket_summary'
  events:
    'change .js-aiAssistanceTicketSummarySetting input': 'toggleAIAssistanceTicketSummarySetting'
    'change .checkbox--service input': 'toggleService'

  elements:
    '.js-aiAssistanceTicketSummarySetting input': 'aiAssistanceTicketSummarySetting'

  constructor: ->
    super

  render: =>
    service_config = App.Setting.get('ai_assistance_ticket_summary_config') || {}

    @html App.view('ai/ticket_summary')(
      description: marked(App.i18n.translateContent(@description, '**Zammad Smart Assist**'))
      contentOptions: @contentOptions(service_config)
      missingProvider: @missingProvider()
    )

  contentOptions: (config) ->
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
        key: 'suggestions'
        description: __('Provide some possible solutions to the problem as follow-up items.')
        active: config.suggestions,
      }
    ]

  toggleAIAssistanceTicketSummarySetting: (e) =>
    value = @aiAssistanceTicketSummarySetting.prop('checked')
    App.Setting.set('ai_assistance_ticket_summary', value, doneLocal: =>
      if @missingProvider()
        App.Event.trigger('ui:rerender')
    )



  toggleService: (e) ->
    value = $(e.currentTarget).prop('checked')
    key = $(e.currentTarget).attr('name')

    config = App.Setting.get('ai_assistance_ticket_summary_config') || {}
    config[key] = value
    App.Setting.set('ai_assistance_ticket_summary_config', config)


App.Config.set('Summary', { prio: 1200, name: __('Ticket Summary'), parent: '#ai', target: '#ai/ticket_summary', controller: App.TicketSummary, permission: ['admin.ai_assistance_ticket_summary'] }, 'NavBarAdmin')
