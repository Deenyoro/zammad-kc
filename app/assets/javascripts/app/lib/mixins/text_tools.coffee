# Methods for initializing and using text tools in a richtext editor

App.TextTools =
  textToolsInit: (el, disabled = false, startCallback = null, stopCallback = null) ->
    return if not App.User.current()?.permission('ticket.agent')
    return if not App.Config.get('ai_provider')
    return if not App.Config.get('ai_assistance_text_tools')

    # Remove any existing text tools, start from scratch.
    #   This is necessary to avoid duplication of text tools in article type switching context.
    el.find('.text-tools').remove()

    # If attachments are present, append text tools to the same container.
    if el.find('.article-attachment:not(.hide)').length and not el.find('.article-attachment .text-tools').length
      el.find('.article-attachment').append( $( App.view('generic/text_tools')(disabled: disabled) ) )
      el.find('.text-tools').css('transform', el.find('.attachmentPlaceholder').css('transform'))

    # Otherwise, append text tools into their own container.
    else if not el.find('.text-tools--standalone').length
      el.append( $( App.view('generic/text_tools')(disabled: disabled, no_attachment: true) ) )

    # Initialize the dropdown menu.
    #  This seems to be necessary only in the article reply context.
    el.find('[data-toggle="dropdown"]').dropdown()

    # Handle text tool actions.
    el.off('click.text-tools-actions', '.js-action').on('click.text-tools-actions', '.js-action', (e) ->
      e.preventDefault()
      action = $(e.target).data('type')
      ce = el.find('[contenteditable]').data().plugin_ce

      el.find('[data-toggle="dropdown"]').dropdown('toggle')

      selection = ce?.getSelection()

      if not selection?.content?.length
        App.Event.trigger('notify', {
          type:    'info'
          msg:     __('Please select some text first.')
          timeout: 2000
        })
        return

      params =
        input: selection.content
        service_type: action

      App.TextTools.textToolsStartLoading(el, startCallback, stopCallback)

      App.Ajax.request(
        id:          'ai_assistance_text_tools'
        type:        'POST'
        url:         "#{App.Config.get('api_path')}/ai_assistance/text_tools"
        data:        JSON.stringify(params)
        processData: true
        success: (data) ->
          App.TextTools.textToolsStopLoading(el, stopCallback)
          ce.replaceSelection(selection.ranges, data.output)
        error: ->
          App.TextTools.textToolsStopLoading(el, stopCallback)
      )
    )

  textToolsStartLoading: (el, startCallback, stopCallback) ->
    startCallback?() # callback is used to temporarily disable the submit button

    loader = $( App.view('generic/text_tools_loading')() )

    loader.off('click.text-tools-cancel', '.js-cancel').on('click.text-tools-cancel', '.js-cancel', (e) ->
      e.preventDefault()
      App.Ajax.abort('ai_assistance_text_tools')
      App.TextTools.textToolsStopLoading(el, stopCallback)
    )

    el.find('[contenteditable]').prop('contenteditable', false)

    if el.find('.article-attachment:not(.hide)').length > 0
      el.find('.article-attachment').hide()
    else
      el.find('.text-tools').hide()

    el.append(loader)

  textToolsStopLoading: (el, stopCallback) ->
    el.find('.js-loading').remove()

    if el.find('.article-attachment:not(.hide)').length > 0
      el.find('.article-attachment').show()
    else
      el.find('.text-tools').show()

    el.find('[contenteditable]')
      .prop('contenteditable', true)
      .focus()

    stopCallback?() # callback is used to re-enable the submit button
