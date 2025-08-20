class App.TextToolsModal extends App.ControllerModal
  buttonClose: true
  buttonCancel: true
  buttonSubmit: __('Approve')

  head: null
  headIcon: 'smart-assist-elaborate'
  headIconClass: 'ai-modal-head-icon'

  selectedText: null
  result: null
  approve: null

  error: false

  onClose:  ->
    App.Ajax.abort('ai_assistance_text_tools')

  constructor: (params) ->
    @textTool = params.textTool
    @head = App.i18n.translatePlain('Writing Assistant: %s', App.i18n.translatePlain(@textTool.name))
    @contextData = params.contextData
    @selectedText = params.selectedText
    @approve = params.approve

    super

    @requestTextTools(
      id:              @textTool.id
      input:           @selectedText
      customer_id:     @contextData.customer_id
      group_id:        @contextData.group_id
      organization_id: @contextData.organization_id
      ticket_id:       @contextData.id
    )

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
      url:         "#{App.Config.get('api_path')}/ai_assistance/text_tools/#{params.id}"
      data:        JSON.stringify(_.omit(params, 'id'))
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

    @requestTextTools(
      id:              @textTool.id
      input:           @selectedText
      customer_id:     @contextData.customer_id
      group_id:        @contextData.group_id
      organization_id: @contextData.organization_id
      ticket_id:       @contextData.id
    )

  onSubmit: =>
    @approve(@result)
    @close()
