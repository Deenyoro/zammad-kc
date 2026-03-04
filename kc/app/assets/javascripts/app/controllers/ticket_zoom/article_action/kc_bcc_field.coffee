# KC: Add BCC field to the email article compose form.
#
# Registered as a TicketZoomArticleAction plugin at priority 160
# (after Note at 100 and KcConvertType at 150, before EmailReply at 200).
#
# How it works:
#   - Model registration: Adds 'bcc' to App.TicketArticle.attributes so that
#     Spine.js includes it in toJSON() / attributes() serialization. Without
#     this, formParam() collects the BCC value but JSON.stringify drops it
#     because Spine only serializes @configure'd attributes.
#   - articleTypes: Adds 'bcc' to the email type's attributes array so the
#     form-group show/hide logic (article_new.coffee line 512-514) includes it.
#   - setArticleTypePost: Injects the BCC form-group DOM element after CC if
#     it doesn't already exist, then applies tokanice for email tokenization.
#   - Access control: Checks kc_bcc_access setting to gate UI visibility.

# Helper to check BCC access based on admin setting
_bccAllowed = ->
  access = App.Setting.get('kc_bcc_access') ? 'all'
  return false if access is 'disabled'
  return false if access is 'admin' and !App.User.current()?.permission('admin')
  true

# Register 'bcc' in the Spine.js model so article.toJSON() includes it.
# This must always be present regardless of setting — the attribute must be
# serializable even if the UI field is hidden.
if App.TicketArticle?.attributes?
  if 'bcc' not in App.TicketArticle.attributes
    App.TicketArticle.attributes.push('bcc')

class KcBccField extends App.Controller
  @action: (actions, ticket, article, ui) ->
    actions

  @perform: (articleContainer, type, ticket, article, ui) ->
    true

  @articleTypes: (articleTypes, ticket, ui) ->
    return articleTypes if !_bccAllowed()
    for articleType in articleTypes
      if articleType.name is 'email'
        if 'bcc' not in articleType.attributes
          articleType.attributes.push('bcc')
    articleTypes

  @setArticleTypePost: (type, ticket, ui, signaturePosition) ->
    return if type isnt 'email'
    return if !_bccAllowed()

    # Check if BCC form-group already exists
    existingBcc = ui.$('[name=bcc]').closest('.form-group')
    if existingBcc.length > 0
      return

    # Find the CC form-group to insert after
    ccGroup = ui.$('[name=cc]').closest('.form-group')
    return if ccGroup.length is 0

    # Build the BCC form-group matching CC's structure
    bccHtml = '<div class="input form-group" data-attribute-name="bcc">' +
      '<div class="formGroup-label"><label for="article_bcc">BCC</label></div>' +
      '<div class="controls">' +
      '<input id="article_bcc" type="text" name="bcc" class="form-control js-mail-inputs js-bcc" autocomplete="off">' +
      '</div>' +
      '</div>'

    ccGroup.after(bccHtml)

    # Apply email tokenization/autocomplete (same as To/CC)
    bccInput = ui.$('.js-bcc')
    if bccInput.length > 0 && App.Utils.tokanice
      App.Utils.tokanice(bccInput, 'email')

App.Config.set('160-KcBccField', KcBccField, 'TicketZoomArticleAction')
