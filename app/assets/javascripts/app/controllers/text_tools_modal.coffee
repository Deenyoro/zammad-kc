class App.TextToolsModal extends App.ControllerModal
  buttonClose: true
  buttonCancel: true
  buttonSubmit: __('Approve')

  head: null
  headIcon: 'smart-assist-elaborate'
  headIconClass: 'ai-modal-head-icon'

  service: 'improve_writing' #  Object.keys of @serviceLabels
  selectedText: null
  result: null
  approve: null

  error: false

  onClose:  ->
    App.Ajax.abort('ai_assistance_text_tools')

  serviceLabels: {
    expand: __('Expand text'),
    simplify: __('Simplify'),
    improve_writing: __('Improve writing'),
    spelling_and_grammar: __('Fix spelling and grammar')
  }

  constructor: (params) ->
    @service = params.service
    @head = App.i18n.translateContent(__('Writing Assistant: %s'), @serviceLabels[@service])
    @selectedText = params.selectedText
    @approve = params.approve

    super

    @requestTextTools({input: @selectedText, service_type: @service})

  disableSubmit: ->
    button = @$('.modal-content').find('.js-submit')
    button.prop('disabled', true) if button.prop

  enableSubmit: ->
    button = @$('.modal-content').find('.js-submit')
    button.prop('disabled', false)  if button.prop

  requestTextTools: (params)  ->
    @disableSubmit()
    @startLoading()

    @ajax(
      id:          'ai_assistance_text_tools'
      type:        'POST'
      url:         "#{App.Config.get('api_path')}/ai_assistance/text_tools"
      data:        JSON.stringify(params)
      processData: true
      failResponseNoTrigger: true
      success: (data) =>
        @stopLoading()
        @result = data.output
        @update()
        @enableSubmit()

      error: =>
        @stopLoading()

        @error = true
        @update()

        @disableSubmit()
        @setupListenerForRetry()
    )

  content: -> $(App.view('generic/text_tools_modal')(
    serviceLabel: @serviceLabels[@service]
    selectedText: @selectedText
    result: @result
    error: @error
  ))

  setupListenerForRetry: =>
    @$('.modal-content').find('.js-retry').on('click',  =>
      @retryTextTools()
    )

  retryTextTools: =>
    @error = false
    @requestTextTools({input: @selectedText, service_type: @service})

  onSubmit: =>
    @approve(@result)
    @close()
