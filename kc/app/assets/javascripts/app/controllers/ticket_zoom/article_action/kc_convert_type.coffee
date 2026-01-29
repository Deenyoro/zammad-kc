# KC: Convert between Note and Email Reply while preserving body content.
# Registered as a TicketZoomArticleAction plugin — auto-discovered by Zammad's
# action config system.  This file is self-contained: if it is removed, the
# feature disappears with zero side-effects.
#
# Integration notes (for future maintainers):
#
#   editControlItem cache
#     Spine.js caches `@editControlItem = @el.find('.editControls-item')` once
#     at render time (via @html → refreshElements).  Our dynamically injected
#     button is NOT in that initial cache.  After every DOM add/remove of the
#     button we must re-assign `ui.editControlItem`.
#
#   openTextarea indiscriminately removes is-hidden
#     `openTextarea` does `@editControlItem.removeClass('is-hidden')` on ALL
#     cached items.  If the button is in the cache but should stay hidden
#     (because the target type does not exist), openTextarea would reveal it.
#     → We solve this by removing the button from DOM entirely when it should
#       not be shown.  `_ensureButton` is idempotent and will re-create it
#       on the next `setArticleTypePost` call when it becomes relevant.
#
#   nth-child positioning
#     `.editControls-item` uses absolute positioning with nth-child CSS rules
#     (child 2 = article type, child 3 = visibility toggle at top:79px,
#     child 4 = top:115px).  Our button is inserted after .js-selectInternalPublic,
#     making it nth-child(4) — which gets top:115px.  We must not change the
#     insertion point or we'll break the positioning of existing controls.
#
#   selectArticleType flow
#     The native handler does: setArticleTypePre → setArticleTypePost → event
#     trigger → tokanice.  Our _onConvert mirrors this exactly.

class KcConvertType

  # ---- constants ----------------------------------------------------------------

  @BUTTON_CLASS:    'js-kcConvertType'

  @TYPE_META:
    note:
      target: 'email'
      icon:   'email'
      title:  'Convert to Email Reply'
    email:
      target: 'note'
      icon:   'note'
      title:  'Convert to Note'

  # ---- plugin interface (called by article_new.coffee) --------------------------

  # We do not add any article types — just return unchanged.
  @articleTypes: (articleTypes, _ticket, _ui) ->
    articleTypes

  # No per-article actions or validations.
  @action:     (actions, _ticket, _article, _ui) -> actions
  @perform:    (_articleContainer, _type, _ticket, _article, _ui) -> true
  @validation: (_type, _params, _ui) -> true
  @params:     (_type, params, _ui) -> params

  # Called after every article-type change (including initial render).
  @setArticleTypePost: (type, _ticket, ui, _signaturePosition) ->
    try
      if @_shouldShow(type, ui)
        @_ensureButton(ui)
        @_updateButtonIcon(type, ui)
      else
        @_removeButton(ui)
    catch e
      console.warn('[KC] ConvertType: setArticleTypePost error', e)

  # ---- private helpers ----------------------------------------------------------

  # Determine whether the button should be present in the DOM at all.
  @_shouldShow: (type, ui) ->
    meta = @TYPE_META[type]
    return false unless meta

    # The target type must actually exist in articleTypes.
    # Example: 'email' only exists when the group has email_address_id.
    return false unless @_typeExists(meta.target, ui)

    true

  # Check if a given article type name is available.
  @_typeExists: (name, ui) ->
    return false unless ui?.articleTypes
    for articleType in ui.articleTypes
      return true if articleType.name is name
    false

  # Inject the button once.  Idempotent — safe to call repeatedly.
  @_ensureButton: (ui) ->
    return unless ui?.el

    container = ui.el.find('.editControls')
    return unless container.length

    # Already injected?
    return if container.find(".#{@BUTTON_CLASS}").length

    # Build the button.  Start with is-hidden so openTextarea can animate it in
    # together with the other editControls-item elements.
    btn = $(
      '<div class="editControls-item is-hidden js-kcConvertType">' +
        '<div class="editControls-iconHolder" style="cursor:pointer">' +
          '<div class="editControls-icon"></div>' +
        '</div>' +
      '</div>'
    )

    # Insert after the visibility toggle — this makes the button nth-child(4)
    # which gets top:115px from Zammad's existing CSS rules.
    anchor = container.find('.js-selectInternalPublic')
    if anchor.length
      anchor.after(btn)
    else
      container.append(btn)

    # Refresh the Spine.js cached editControlItem jQuery set so that
    # openTextarea / closeTextarea animations include this button.
    ui.editControlItem = ui.el.find('.editControls-item')

    # If the compose area is already open, reveal immediately (the animation
    # train has already left the station — is-hidden would keep us invisible).
    if ui.el.find('.article-add').hasClass('is-open')
      btn.removeClass('is-hidden')

    # Bind click handler (closure keeps class ref for `self`)
    self = @
    btn.on 'click', (e) ->
      e.stopPropagation()
      try
        self._onConvert(ui)
      catch err
        console.warn('[KC] ConvertType: click handler error', err)

  # Remove the button from DOM and refresh the element cache.
  # This prevents openTextarea from revealing a button that should not be shown.
  @_removeButton: (ui) ->
    return unless ui?.el
    btn = ui.el.find(".#{@BUTTON_CLASS}")
    return unless btn.length

    btn.remove()
    ui.editControlItem = ui.el.find('.editControls-item')

  # Update the button's icon and tooltip for the current type.
  @_updateButtonIcon: (type, ui) ->
    return unless ui?.el

    btn = ui.el.find(".#{@BUTTON_CLASS}")
    return unless btn.length

    meta = @TYPE_META[type]
    return unless meta

    iconHolder = btn.find('.editControls-icon')
    iconHolder.empty()

    if App?.Utils?.icon
      iconHolder.append(App.Utils.icon(meta.icon))
    else
      iconHolder.text(meta.title)

    title = if App?.i18n?.translateInline then App.i18n.translateInline(meta.title) else meta.title
    iconHolder.attr('title', title)

  # ---- conversion logic ---------------------------------------------------------

  # Perform the actual note ↔ email conversion.
  @_onConvert: (ui) ->
    return unless ui?.el

    currentType = ui.type
    meta = @TYPE_META[currentType]
    return unless meta

    targetType = meta.target

    # Guard: target type must still be available (could have vanished if group
    # changed between button render and click).
    return unless @_typeExists(targetType, ui)

    # 1. Capture the current body before the type switch.
    bodyEl = ui.el.find('[data-name="body"]')
    bodyHtml = bodyEl.html() if bodyEl.length

    # 2. Switch the type — mirrors selectArticleType flow exactly:
    #    setArticleTypePre → setArticleTypePost → event trigger → tokanice
    #
    #    Note: setArticleTypePre resets to/cc/bcc/subject (line 478-480 of
    #    article_new.coffee) but does NOT touch body.  It also does NOT call
    #    plugin setArticleTypePre methods — only setArticleTypePost does.
    ui.setArticleTypePre(targetType)

    # 3. Restore body defensively.  setArticleTypePre should preserve it, but
    #    guard against future upstream changes that might clear it.
    if bodyHtml? && bodyEl.length
      freshBodyEl = ui.el.find('[data-name="body"]')
      if freshBodyEl.length && freshBodyEl.html() != bodyHtml
        freshBodyEl.html(bodyHtml)

    # 4. Finalize the type switch (iterates all plugins: inserts/removes
    #    signatures, updates our button icon, etc.)
    ui.setArticleTypePost(targetType)

    # 5. If switching to email, populate the To field with the ticket customer.
    #    Done AFTER setArticleTypePost so that EmailReply.setArticleTypePost has
    #    already finished signature insertion and the DOM is stable.
    if targetType is 'email'
      @_populateRecipient(ui)

    # 6. Trigger change event so Zammad's task state tracking picks it up.
    App?.Event?.trigger?('ui::ticket::articleNew::change', { ticket_id: ui.ticket?.id || ui.ticket_id })

    # 7. Ensure tokenization runs for email address fields.
    ui.tokanice?(targetType)

  # Populate the To field with the ticket's customer email address.
  @_populateRecipient: (ui) ->
    try
      ticketId = ui.ticket?.id || ui.ticket_id
      return unless ticketId

      ticket = App?.Ticket?.fullLocal?(ticketId)
      return unless ticket

      customerId = ticket.customer_id
      return unless customerId

      customer = App?.User?.find?(customerId)
      return unless customer?.email

      toField = ui.el.find('[name="to"]')
      return unless toField.length

      # .val() + trigger('change') is how the upstream ui::ticket::setArticleType
      # event handler populates fields (article_new.coffee line 69).
      toField.val(customer.email).trigger('change')
    catch e
      console.warn('[KC] ConvertType: _populateRecipient error', e)

# ---- registration ---------------------------------------------------------------
# Priority 150 — between Note (100) and EmailReply (200).
App.Config.set('150-KcConvertType', KcConvertType, 'TicketZoomArticleAction')
