# KC: Scheduled reply banner in the ticket timeline.
#
# Displays pending scheduled replies as banner cards at the bottom of the
# article list. Each banner shows the scheduled time, a preview of the
# reply body, and a cancel button.
#
# Registered as a Plugin for auto-initialization.
#
# HARDENING:
#   - All operations wrapped in try/catch
#   - Graceful hide if API returns 404 or error
#   - Event-driven refresh via kc::scheduled_reply::changed
#   - Proper event cleanup in release() to prevent memory leaks
#   - Scoped DOM selectors to active content only
class KcScheduledReplyBanner extends App.Controller
  PREVIEW_MAX_LENGTH: 200

  constructor: ->
    super
    try
      # Store bound handler references for proper cleanup
      @onScheduledReplyChanged = (data) =>
        try
          @fetchAndRender(data.ticket_id) if data?.ticket_id
        catch e
          console.warn '[KC] kc::scheduled_reply::changed handler failed', e

      @onTicketShown = (data) =>
        try
          return if !data?.ticket_id
          @delay(=>
            @fetchAndRender(data.ticket_id)
          , 500, "kc-scheduled-banner-#{data.ticket_id}")
        catch e
          console.warn '[KC] ui::ticket::shown handler failed', e

      App.Event.bind('kc::scheduled_reply::changed', @onScheduledReplyChanged)
      App.Event.bind('ui::ticket::shown', @onTicketShown)

      # Delegate cancel click
      $(document).on('click.kcScheduledBanner', '.js-cancelScheduledReply', @onCancelClick)
    catch e
      console.warn '[KC] KcScheduledReplyBanner init failed', e

  release: =>
    try
      $(document).off('.kcScheduledBanner')
      # Unbind all bound events with handler references
      App.Event.unbind('kc::scheduled_reply::changed', @onScheduledReplyChanged) if @onScheduledReplyChanged
      App.Event.unbind('ui::ticket::shown', @onTicketShown) if @onTicketShown
      @onScheduledReplyChanged = null
      @onTicketShown = null
    catch e
      console.warn '[KC] KcScheduledReplyBanner release failed', e

  # ---------- Fetch and render ----------

  fetchAndRender: (ticketId) =>
    return if !ticketId
    try
      @ajax(
        id:      "kc_scheduled_banners_#{ticketId}"
        type:    'GET'
        url:     "#{@apiPath}/kc/tickets/#{ticketId}/scheduled_articles"
        timeout: 10000
        success: (data) =>
          try
            @renderBanners(ticketId, data || [])
          catch e
            console.warn '[KC] renderBanners failed', e
        error: (xhr) =>
          # Silently hide on error — feature not available
          try
            @removeBanners(ticketId)
          catch
            # noop
      )
    catch e
      console.warn '[KC] fetchAndRender failed', e

  renderBanners: (ticketId, scheduled) =>
    # Scoped to active content only to avoid cross-tab rendering
    contentEl = $(".content.active .ticket-article").first()
    return if contentEl.length is 0

    # Remove existing banners first
    contentEl.find('.kc-scheduled-reply-container').remove()

    return if !scheduled || scheduled.length is 0

    # Build items with preview data
    items = []
    for s in scheduled
      articleData = s.article_data || {}
      bodyPreview = @truncateHtml(articleData.body || '', @PREVIEW_MAX_LENGTH)
      items.push({
        id:           s.id
        scheduled_at: s.scheduled_at
        article_type: @humanArticleType(articleData.type)
        to:           articleData.to || ''
        cc:           articleData.cc || ''
        body_preview: bodyPreview
        ticket_id:    ticketId
      })

    html = App.view('kc_scheduled_reply_banner')(
      items: items
    )

    container = $('<div>')
      .addClass('kc-scheduled-reply-container')
      .attr('data-ticket-id', ticketId)
    container.html(html)
    contentEl.append(container)

  removeBanners: (ticketId) =>
    $(".kc-scheduled-reply-container[data-ticket-id='#{ticketId}']").remove()

  # ---------- Cancel ----------

  onCancelClick: (e) =>
    try
      e.preventDefault()
      e.stopPropagation()

      scheduledId = $(e.currentTarget).data('id')
      return if !scheduledId

      bannerEl = $(e.currentTarget).closest('.kc-scheduled-reply')
      containerEl = bannerEl.closest('.kc-scheduled-reply-container')
      ticketId = containerEl.data('ticket-id')

      if !ticketId
        # Try to find from active task
        match = window.location.hash.match(/ticket\/zoom\/(\d+)/)
        ticketId = parseInt(match[1]) if match

      return if !ticketId

      new App.ControllerConfirm(
        message:     __('Cancel this scheduled reply?')
        buttonClass: 'btn--danger'
        callback: =>
          @ajax(
            id:      "kc_cancel_scheduled_#{scheduledId}"
            type:    'DELETE'
            url:     "#{@apiPath}/kc/tickets/#{ticketId}/scheduled_articles/#{scheduledId}"
            timeout: 10000
            success: =>
              @notify(type: 'success', msg: __('Scheduled reply cancelled'))
              bannerEl.fadeOut(300, ->
                bannerEl.remove()
                # Remove container if empty
                if containerEl.find('.kc-scheduled-reply').length is 0
                  containerEl.remove()
              )
              App.Event.trigger('kc::scheduled_reply::changed', { ticket_id: ticketId })
            error: (xhr) =>
              errorMsg = xhr.responseJSON?.error || __('Failed to cancel scheduled reply')
              @notify(type: 'error', msg: errorMsg)
          )
        container: $(e.currentTarget).closest('.content')
      )
    catch e
      console.warn '[KC] onCancelClick failed', e

  # ---------- Helpers ----------

  # Maps internal article type names to human-readable labels for the banner.
  ARTICLE_TYPE_LABELS:
    'email':                    'Email'
    'teams_chat_message':       'Teams Chat'
    'ringcentral_sms_message':  'RingCentral SMS'
    'note':                     'Note'
    'phone':                    'Phone'
    'web':                      'Web'

  humanArticleType: (typeName) ->
    return '' if !typeName
    label = @ARTICLE_TYPE_LABELS[typeName]
    return label if label
    # Escape unknown type names to prevent XSS via @T() passthrough
    $('<span>').text(typeName).html()

  truncateHtml: (html, maxLength) ->
    return '' if !html
    # Strip HTML tags for plain-text preview, then truncate.
    # Uses DOMParser for safe parsing (no script execution in detached context).
    try
      doc = new DOMParser().parseFromString(html, 'text/html')
      text = doc.body?.textContent || ''
    catch
      text = $('<div>').text(html).text()
    if text.length > maxLength
      text = text.substring(0, maxLength) + '...'
    text

App.Config.set('KcScheduledReplyBanner', KcScheduledReplyBanner, 'Plugins')
