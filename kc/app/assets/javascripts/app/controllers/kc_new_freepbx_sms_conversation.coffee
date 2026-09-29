# KC: Agent page for starting a new text conversation through FreePBX.
#
# Adds "New SMS Message (FreePBX)" to the "+" dropdown in the top nav bar.
# The entry is only shown while FreePBX texting is switched on
# (kc_freepbx_sms_enabled); the nav bar re-evaluates the setting on every
# render, so turning it off hides the entry without a reload.
#
# Mirrors kc_new_sms_conversation.coffee (RingCentral); the sender is one of
# the PBX numbers the connector reports instead of a RingCentral account.

class KcNewFreepbxSmsConversation extends App.ControllerPermanent
  @requiredPermission: ['ticket.agent']

  constructor: (params) ->
    super
    @authenticateCheckRedirect()

    App.TaskManager.execute(
      key:        'KcNewFreepbxSmsConversation'
      controller: 'KcNewFreepbxSmsConversationContent'
      params:     params
      show:       true
      persistent: true
    )

class App.KcNewFreepbxSmsConversationContent extends App.Controller
  events:
    'submit .js-smsForm':        'onSubmit'
    'input .js-recipientSearch': 'onRecipientSearch'
    'click .js-clearRecipient':  'onClearRecipient'
    'change .js-skipSend':       'onSkipSendToggle'
    'input .js-phoneNumber':     'onPhoneInput'

  constructor: ->
    super
    @render()

  render: ->
    groups = App.Group.all().filter (g) -> g.active
    defaultGroupId = groups[0]?.id

    @html App.view('kc_new_freepbx_sms_conversation/index')(
      groups:         groups
      defaultGroupId: defaultGroupId
    )

    @searchTimer = null
    @recipientResults = @el.find('.js-recipientResults')
    @loadNumbers()

    @outsideClickHandler = (e) =>
      return if $(e.target).closest('.js-recipientResults, .js-recipientSearch').length
      @recipientResults.hide().empty()
    $(document).on('click.kcFreepbxSmsRecipient', @outsideClickHandler)

  release: ->
    clearTimeout(@searchTimer) if @searchTimer
    $(document).off('click.kcFreepbxSmsRecipient')
    super

  loadNumbers: ->
    @ajax(
      id:   'kc-freepbx-sms-numbers'
      type: 'GET'
      url:  "#{App.Config.get('api_path')}/kc/conversations/freepbx_sms_numbers"
      success: (data) =>
        select = @el.find('.js-fromNumber')
        select.empty()
        numbers = data.numbers || []
        defaultNumber = (data.default_number || '').toString()
        for entry in numbers
          option = $('<option>').val(entry.number).text(entry.label || entry.number)
          option.prop('selected', true) if defaultNumber && entry.number is defaultNumber
          select.append(option)
        if !data.enabled
          @el.find('.js-disabledHint').show()
          @el.find('.js-submit').prop('disabled', true)
        else if numbers.length is 0
          select.append($('<option>').val('').text(App.i18n.translateInline('No texting numbers reported by the PBX')))
          @el.find('.js-noNumbersHint').show()
          @el.find('.js-submit').prop('disabled', true)
      error: =>
        @el.find('.js-fromNumber').html('<option value="">' + App.i18n.translateInline('Failed to load numbers') + '</option>')
    )

  onRecipientSearch: (e) ->
    query = $(e.target).val().trim()
    if query.length < 2
      @recipientResults.hide().empty()
      return

    clearTimeout(@searchTimer) if @searchTimer
    @searchTimer = setTimeout(=>
      @searchUsers(query)
    , 300)

  searchUsers: (query) ->
    @ajax(
      id:   'kc-freepbx-sms-user-search'
      type: 'GET'
      url:  "#{App.Config.get('api_path')}/kc/conversations/sms_users?query=#{encodeURIComponent(query)}"
      success: (data) =>
        @renderRecipientResults(data.users || [])
      error: =>
        @recipientResults.hide().empty()
    )

  normalizePhone: (raw) ->
    return '' unless raw
    digits = raw.replace(/[^\d]/g, '')
    return '' unless digits.length >= 7
    if digits.length is 10
      "+1#{digits}"
    else if digits.length is 11 and digits[0] is '1'
      "+#{digits}"
    else
      "+#{digits}"

  renderRecipientResults: (users) ->
    if users.length is 0
      @recipientResults.hide().empty()
      return

    html = ''
    for user in users
      name = user.name || ''
      numbers = []
      numbers.push({ label: 'phone', value: user.phone })  if user.phone
      numbers.push({ label: 'mobile', value: user.mobile }) if user.mobile and user.mobile isnt user.phone
      continue if numbers.length is 0
      for num in numbers
        tag = if numbers.length > 1 then " (#{num.label})" else ''
        html += """
          <div class="js-selectRecipient" data-id="#{user.id}" data-phone="#{App.Utils.htmlEscape(num.value)}" data-name="#{App.Utils.htmlEscape(name)}"
               style="padding:8px 12px; cursor:pointer; border-bottom:1px solid var(--border);"
               onmouseover="this.style.background='rgba(0,0,0,.05)'" onmouseout="this.style.background='transparent'">
            <strong>#{App.Utils.htmlEscape(name)}#{App.Utils.htmlEscape(tag)}</strong>
            <span style="opacity:.7; margin-left:8px;">#{App.Utils.htmlEscape(num.value)}</span>
          </div>
        """

    if !html
      @recipientResults.hide().empty()
      return

    @recipientResults.html(html).show()

    @recipientResults.find('.js-selectRecipient').on('click', (e) =>
      el = $(e.currentTarget)
      rawPhone = el.data('phone')?.toString() || ''
      @addRecipient(@normalizePhone(rawPhone), el.data('id'), el.data('name'))
      @recipientResults.hide().empty()
    )

  parsePhones: (raw) ->
    seen = {}
    result = []
    for part in (raw || '').split(/[,;\n]+/)
      part = part.trim()
      continue unless part
      normalized = @normalizePhone(part)
      return null unless normalized
      continue if seen[normalized]
      seen[normalized] = true
      result.push(normalized)
    result

  addRecipient: (phone, customerId, name) ->
    return unless phone
    field   = @el.find('.js-phoneNumber')
    current = @parsePhones(field.val()) || []
    unless phone in current
      current.push(phone)
    field.val(current.join(', '))
    @el.find('.js-customerId').val(customerId) if current.length is 1
    @el.find('.js-recipientSearch').val('')
    @el.find('.js-clearRecipient').show()
    @updateRecipientHint()

  updateRecipientHint: ->
    phones = @parsePhones(@el.find('.js-phoneNumber').val()) || []
    hint = @el.find('.js-groupHint')
    if phones.length > 1
      hint.text(App.i18n.translateInline('Group text to %s recipients', phones.length)).show()
    else
      hint.hide()

  onClearRecipient: (e) ->
    e.preventDefault()
    @el.find('.js-phoneNumber').val('')
    @el.find('.js-customerId').val('')
    @el.find('.js-recipientSearch').val('').focus()
    @el.find('.js-clearRecipient').hide()
    @updateRecipientHint()

  onPhoneInput: ->
    @updateRecipientHint()

  onSkipSendToggle: (e) ->
    if $(e.currentTarget).is(':checked')
      @el.find('.js-submit').text(App.i18n.translateInline('Create Ticket'))
    else
      @el.find('.js-submit').text(App.i18n.translateInline('Send SMS'))

  onSubmit: (e) ->
    e.preventDefault()

    rawPhone   = @el.find('.js-phoneNumber').val()?.trim()
    body       = @el.find('.js-body').val()?.trim()
    groupId    = @el.find('.js-group').val()
    customerId = @el.find('.js-customerId').val()
    fromNumber = @el.find('.js-fromNumber').val()
    skipSend   = @el.find('.js-skipSend').is(':checked')

    if !rawPhone || !body
      @showError(__('Phone number and message are required.'))
      return

    phoneNumbers = @parsePhones(rawPhone)
    if !phoneNumbers || phoneNumbers.length is 0
      @showError(__('Please enter a valid phone number.'))
      return
    if phoneNumbers.length > 10
      @showError(__('A group text can have at most 10 recipients.'))
      return
    @el.find('.js-phoneNumber').val(phoneNumbers.join(', '))

    @hideError()
    @el.find('.js-submit').prop('disabled', true)
    @el.find('.js-loading').show()
    loadingText = if skipSend then App.i18n.translateInline('Creating ticket...') else App.i18n.translateInline('Sending...')
    @el.find('.js-loadingText').text(loadingText)

    @ajax(
      id:   'kc-new-freepbx-sms-conversation'
      type: 'POST'
      url:  "#{App.Config.get('api_path')}/kc/conversations/freepbx_sms"
      data: JSON.stringify(
        phone_number:  phoneNumbers[0]
        phone_numbers: phoneNumbers
        body:          body
        group_id:      groupId
        customer_id:   customerId
        from_number:   fromNumber
        skip_send:     skipSend
      )
      contentType: 'application/json'
      success: (data) =>
        @el.find('.js-submit').prop('disabled', false)
        @el.find('.js-loading').hide()
        @navigate "#ticket/zoom/#{data.id}"
      error: (xhr) =>
        @el.find('.js-submit').prop('disabled', false)
        @el.find('.js-loading').hide()
        try
          msg = JSON.parse(xhr.responseText)?.error || __('Failed to send SMS')
        catch
          msg = __('Failed to send SMS')
        @showError(msg)
    )

  showError: (msg) ->
    @el.find('.js-error').text(msg).show()

  hideError: ->
    @el.find('.js-error').hide()

App.Config.set('kc/new_freepbx_sms', KcNewFreepbxSmsConversation, 'Routes')
App.Config.set('KcNewFreepbxSms', {
  prio:       8006
  parent:     '#new'
  name:       __('New SMS Message (FreePBX)')
  translate:  true
  target:     '#kc/new_freepbx_sms'
  permission: ['ticket.agent']
  setting:    ['kc_freepbx_sms_enabled']
}, 'NavBarRight')
