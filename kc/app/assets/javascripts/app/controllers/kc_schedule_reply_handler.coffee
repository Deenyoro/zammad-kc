# KC: Schedule Reply dropdown injection and orchestration.
#
# This controller:
#   1. Injects a "Schedule Reply" item into the ticket update dropdown
#   2. Opens the datetime picker modal on click
#   3. Collects article params and POSTs to the scheduled articles API
#   4. Resets the article form on success
#
# Registered as a Plugin so it auto-initializes with the application.
#
# HARDENING:
#   - All DOM manipulation wrapped in try/catch
#   - Graceful degradation if ticket zoom is not visible
#   - MutationObserver with debounce ensures the menu item persists across re-renders
#   - Safe DOM element construction (no raw HTML string concatenation)
#   - Article params cloned before mutation to avoid side effects
#   - Double-click guard prevents multiple modals
#   - Controller validation before taskReset prevents stale reference errors
class KcScheduleReplyHandler extends App.Controller
  constructor: ->
    super
    try
      @modalOpen = false

      # Delegate click handler on body for our custom dropdown item
      $(document).on('mouseup.kcScheduleReply', '.js-dropdownActionScheduleReply', @onScheduleReplyClick)

      # Inject into any existing dropdowns now
      @injectAll()

      # Watch for DOM changes to re-inject when dropdown is re-rendered
      @startObserver()
    catch e
      console.warn '[KC] KcScheduleReplyHandler init failed', e

  release: =>
    try
      @modalOpen = false
      $(document).off('.kcScheduleReply')
      @stopObserver()
    catch e
      console.warn '[KC] KcScheduleReplyHandler release failed', e

  # ---------- DOM injection ----------

  injectAll: =>
    try
      $('.js-submitDropdown .dropdown-menu').each (i, menu) =>
        @injectIntoMenu($(menu))
    catch e
      console.warn '[KC] injectAll failed', e

  injectIntoMenu: (menu) =>
    return if !menu || menu.length is 0
    return if menu.find('.js-dropdownActionScheduleReply').length > 0

    # Build elements programmatically instead of raw HTML string concatenation
    headerLi = $('<li>').addClass('dropdown-header').attr('role', 'menuitem')
      .text(App.i18n.translateInline('Schedule'))
    actionLi = $('<li>').addClass('js-dropdownActionScheduleReply').attr('role', 'menuitem')
      .attr('tabindex', '0')
      .text(App.i18n.translateInline('Schedule Reply'))

    # Insert before the first dropdown-header (Draft or Macros) or at top
    firstHeader = menu.find('.dropdown-header').first()
    if firstHeader.length > 0
      firstHeader.before(actionLi)
      actionLi.before(headerLi)
    else
      menu.prepend(actionLi)
      menu.prepend(headerLi)

  # ---------- MutationObserver ----------

  startObserver: =>
    return if typeof MutationObserver is 'undefined'
    try
      @observer = new MutationObserver (mutations) =>
        needsInject = false
        for mutation in mutations
          if mutation.addedNodes?.length > 0
            needsInject = true
            break
        # Debounce: only inject once per 300ms to avoid performance issues
        # from high-frequency DOM mutations (e.g., article list rendering)
        if needsInject
          @delay(@injectAll, 300, 'kc-schedule-reply-inject')

      # Observe the main app area where ticket zoom lives
      appEl = document.querySelector('#app')
      if appEl
        @observer.observe(appEl, { childList: true, subtree: true })
    catch e
      console.warn '[KC] startObserver failed', e

  stopObserver: =>
    try
      @observer?.disconnect()
      @observer = null
    catch e
      console.warn '[KC] stopObserver failed', e

  # ---------- Click handler ----------

  onScheduleReplyClick: (e) =>
    try
      # Only handle left mouse button for mouseup events
      return if e.type is 'mouseup' and e.button isnt 0

      e.preventDefault()
      e.stopPropagation()

      # Guard against double-click opening multiple modals
      return if @modalOpen

      # Close the dropdown
      dropdownEl = $(e.currentTarget).closest('.js-submitDropdown')
      dropdownEl.removeClass('is-open')

      # Find the ticket zoom controller via the closest content wrapper
      contentEl = $(e.currentTarget).closest('.content.active')
      if contentEl.length is 0
        contentEl = $(e.currentTarget).closest('.content')

      ticketId = @findTicketId(contentEl)
      if !ticketId
        @notify(type: 'error', msg: __('Could not determine ticket'))
        return

      # Get article params from the active ticket zoom
      taskKey = "Ticket-#{ticketId}"
      controller = App.TaskManager.worker(taskKey)

      if !controller
        @notify(type: 'error', msg: __('Ticket controller not found'))
        return

      articleParams = controller.articleParams?()
      if !articleParams || !articleParams.body || articleParams.body.trim() is '' || articleParams.body is '<br>'
        @notify(type: 'error', msg: __('Please compose a reply before scheduling'))
        return

      # Clone article params to avoid mutating the controller's state
      clonedParams = $.extend(true, {}, articleParams)

      # Include form_id so attachments can be transferred
      formId = controller.form_id
      clonedParams.form_id = formId if formId

      # Store context for the modal callback
      @pendingTicketId = ticketId
      @pendingController = controller
      @pendingArticleParams = clonedParams

      # Show the datetime picker modal
      @modalOpen = true
      new App.KcScheduleReplyModal(
        container:      contentEl
        submitCallback: @onScheduleConfirm
        onClose: => @modalOpen = false
      )
    catch e
      @modalOpen = false
      console.warn '[KC] onScheduleReplyClick failed', e
      @notify(type: 'error', msg: __('Failed to open schedule dialog'))

  # ---------- Schedule confirm ----------

  onScheduleConfirm: (params) =>
    try
      ticketId      = @pendingTicketId
      controller    = @pendingController
      articleParams = @pendingArticleParams

      # Clear pending state immediately to prevent double-submit
      @pendingTicketId = null
      @pendingController = null
      @pendingArticleParams = null

      return if !ticketId || !articleParams

      # Collect ticket attribute changes
      ticketAttributes = {}
      try
        ticketAttributes = controller.ticketParams?() || {}
      catch
        ticketAttributes = {}

      @ajax(
        id:          "kc_schedule_reply_#{ticketId}_#{Date.now()}"
        type:        'POST'
        url:         "#{@apiPath}/kc/tickets/#{ticketId}/scheduled_articles"
        data:        JSON.stringify(
          article_data:      articleParams
          ticket_attributes: ticketAttributes
          scheduled_at:      params.scheduled_at
        )
        contentType: 'application/json'
        processData: false
        timeout:     15000
        success: (data) =>
          @notify(type: 'success', msg: __('Reply scheduled successfully'))

          # Reset the article form — verify controller is still active
          try
            taskKey = "Ticket-#{ticketId}"
            activeController = App.TaskManager.worker(taskKey)
            if activeController is controller
              controller.taskReset()
          catch e
            console.warn '[KC] taskReset failed', e

          # Trigger event so the banner can refresh
          App.Event.trigger('kc::scheduled_reply::changed', { ticket_id: ticketId })

        error: (xhr) =>
          errorMsg = xhr.responseJSON?.error || __('Failed to schedule reply')
          @notify(type: 'error', msg: errorMsg)
      )
    catch e
      console.warn '[KC] onScheduleConfirm failed', e
      @notify(type: 'error', msg: __('Failed to schedule reply'))

  # ---------- Helpers ----------

  findTicketId: (contentEl) ->
    try
      # Try to extract from the URL hash
      match = window.location.hash.match(/ticket\/zoom\/(\d+)/)
      if match
        id = parseInt(match[1])
        return id if !isNaN(id)

      # Try from the content element's data or the active task
      activeTask = App.TaskManager.getActive()
      if activeTask?.key
        ticketMatch = activeTask.key.match(/Ticket-(\d+)/)
        if ticketMatch
          id = parseInt(ticketMatch[1])
          return id if !isNaN(id)
    catch e
      console.warn '[KC] findTicketId failed', e

    null

App.Config.set('KcScheduleReplyHandler', KcScheduleReplyHandler, 'Plugins')
