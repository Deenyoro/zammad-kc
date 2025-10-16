class App.AIFeedbackWidget extends App.Controller
  runId: null
  hasProvidedFeedback: false
  regenerateCallback: null

  elements:
    '.js-aiFeedbackQuestion':       'question'
    '.js-aiFeedbackToolbar':        'toolbar'
    '.js-aiFeedbackButtons':        'buttons'
    '.js-aiFeedbackAcknowledgment': 'acknowledgment'
    '.js-aiFeedbackComment':        'comment'

  events:
    'click .js-aiPositiveReaction': 'submitPositiveReaction'
    'click .js-aiNegativeReaction': 'submitNegativeReaction'
    'click .js-aiRegenerate':       'regenerateResult'
    'click .js-aiCommentCancel':    'cancelComment'
    'click .js-aiCommentSubmit':    'submitComment'

  constructor: ->
    super

    @render()

  render: =>
    @html App.view('ai/ai_feedback_widget')(
      runId:               @runId
      hasRegenerate:       typeof @regenerateCallback is 'function'
      hasProvidedFeedback: @hasProvidedFeedback
    )

  recordUsage: (payload = {}, callback = null) =>
    return if not @runId

    @el.find('.btn, .form-control').prop('disabled', true)

    payload.ai_analytics_run_id = @runId

    @ajax(
      id:          'ai_analytics_usage_update'
      type:        'PUT'
      url:         "#{@apiPath}/ai/analytics/usages"
      data:        JSON.stringify(payload)
      processData: true
      success:     (data, status, xhr) =>
        @el.find('.btn, .form-control').prop('disabled', false)
        callback?(data, status, xhr)
    )

  submitPositiveReaction: ->
    @recordUsage(rating: true, =>
      @hideQuestionAndButtons()
      @showAcknowledgment()
    )

  submitNegativeReaction: ->
    @recordUsage(rating: false, =>
      @hideQuestionAndButtons()
      @hideToolbar()
      @showComment()
    )

  regenerateResult: ->
    @el.find('.btn').prop('disabled', true)
    @regenerateCallback?(@runId)

  cancelComment: ->
    @hideComment()
    @showToolbar()
    @showAcknowledgment()

  submitComment: ->
    if commentText = @comment.find('textarea').val()
      @recordUsage(comment: commentText, =>
        @hideComment()
        @showToolbar()
        @showAcknowledgment()
      )
    else
      @hideComment()
      @showToolbar()
      @showAcknowledgment()

  hideQuestionAndButtons: ->
    @question.addClass('hide')
    @buttons.addClass('hide')

  showToolbar: ->
    @toolbar.removeClass('hide')

  hideToolbar: ->
    @toolbar.addClass('hide')

  showAcknowledgment: ->
    @acknowledgment.removeClass('hide')

  showComment: ->
    @comment.removeClass('hide')
    return if @comment.visible()

    @comment
      .ScrollTo()
      .find('textarea')
      .focus()

  hideComment: ->
    @comment.addClass('hide')
