# KC: "Send with text color" dropdown injection.
#
# This controller:
#   1. Injects a "Send with text color" item into the ticket update dropdown
#   2. On click, sets a flag and triggers the normal submit
#   3. Intercepts the AJAX PUT to inject `article.preferences.kc_preserve_text_color`
#   4. Only shows when kc_strip_email_text_color setting is enabled
#
# Registered as a Plugin so it auto-initializes with the application.
#
# HARDENING:
#   - All DOM manipulation wrapped in try/catch
#   - MutationObserver with debounce for re-injection on DOM changes
#   - AJAX intercept is scoped — only modifies the PUT when the flag is set
#   - Flag is cleared immediately after interception to prevent leaking
#   - Safe DOM element construction (no raw HTML string concatenation)
class KcSendWithColorHandler extends App.Controller
  constructor: ->
    super
    try
      @sendWithColor = false

      # Delegate click handler
      $(document).on('mouseup.kcSendWithColor', '.js-dropdownActionSendWithColor', @onSendWithColorClick)

      # Inject into existing dropdowns
      @injectAll()

      # Watch for DOM changes
      @startObserver()
    catch e
      console.warn '[KC] KcSendWithColorHandler init failed', e

  release: =>
    try
      @sendWithColor = false
      $(document).off('.kcSendWithColor')
      @stopObserver()
    catch e
      console.warn '[KC] KcSendWithColorHandler release failed', e

  # ---------- DOM injection ----------

  # Use App.Config.get() — frontend settings are delivered via the login
  # response into App.Config, NOT into the App.Setting Spine collection.
  isEnabled: ->
    App.Config.get('kc_strip_email_text_color') isnt false

  injectAll: =>
    try
      return if !@isEnabled()

      $('.js-submitDropdown .dropdown-menu').each (i, menu) =>
        @injectIntoMenu($(menu))
    catch e
      console.warn '[KC] injectAll (color) failed', e

  injectIntoMenu: (menu) =>
    return if !menu || menu.length is 0
    return if menu.find('.js-dropdownActionSendWithColor').length > 0

    # Build elements programmatically
    headerLi = $('<li>').addClass('dropdown-header kc-send-with-color-header').attr('role', 'menuitem')
      .text(App.i18n.translateInline('Color'))
    actionLi = $('<li>').addClass('js-dropdownActionSendWithColor').attr('role', 'menuitem')
      .attr('tabindex', '0')
      .text(App.i18n.translateInline('Send with text color'))

    # Insert before the first dropdown-header or at top
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
        if needsInject
          @delay(@injectAll, 300, 'kc-send-with-color-inject')

      appEl = document.querySelector('#app')
      if appEl
        @observer.observe(appEl, { childList: true, subtree: true })
    catch e
      console.warn '[KC] startObserver (color) failed', e

  stopObserver: =>
    try
      @observer?.disconnect()
      @observer = null
    catch e
      console.warn '[KC] stopObserver (color) failed', e

  # ---------- Click handler ----------

  onSendWithColorClick: (e) =>
    try
      # Only handle left mouse button
      return if e.type is 'mouseup' and e.button isnt 0

      e.preventDefault()
      e.stopPropagation()

      # Close the dropdown
      dropdownEl = $(e.currentTarget).closest('.js-submitDropdown')
      dropdownEl.removeClass('is-open')

      # Set the flag and register the AJAX interceptor
      @sendWithColor = true
      @registerAjaxInterceptor()

      # Trigger the normal submit button click
      contentEl = $(e.currentTarget).closest('.content.active')
      if contentEl.length is 0
        contentEl = $(e.currentTarget).closest('.content')

      submitBtn = contentEl.find('.js-submit')
      if submitBtn.length > 0
        submitBtn.first().trigger('click')
      else
        @sendWithColor = false
        @unregisterAjaxInterceptor()
        console.warn '[KC] Could not find submit button'
    catch e
      @sendWithColor = false
      @unregisterAjaxInterceptor()
      console.warn '[KC] onSendWithColorClick failed', e

  # ---------- AJAX interceptor ----------

  registerAjaxInterceptor: =>
    # Use a one-shot AJAX prefilter via ajaxSend
    $(document).on('ajaxSend.kcSendWithColor', @onAjaxSend)

    # Safety: clear flag after 10 seconds if no AJAX fires
    @delay(=>
      if @sendWithColor
        @sendWithColor = false
        @unregisterAjaxInterceptor()
    , 10000, 'kc-send-with-color-timeout')

  unregisterAjaxInterceptor: =>
    $(document).off('ajaxSend.kcSendWithColor')

  onAjaxSend: (event, jqXHR, settings) =>
    try
      return unless @sendWithColor

      # Only intercept PUT requests to tickets API
      return unless settings.type is 'PUT' and /\/api\/v1\/tickets\/\d+/.test(settings.url)

      # Parse and modify the request body
      if settings.data and typeof settings.data is 'string'
        data = JSON.parse(settings.data)

        if data.article
          data.article.preferences ?= {}
          data.article.preferences.kc_preserve_text_color = true
          settings.data = JSON.stringify(data)

      # Clear the flag — one-shot only
      @sendWithColor = false
      @unregisterAjaxInterceptor()
    catch e
      @sendWithColor = false
      @unregisterAjaxInterceptor()
      console.warn '[KC] onAjaxSend (color) failed', e

App.Config.set('KcSendWithColorHandler', KcSendWithColorHandler, 'Plugins')
