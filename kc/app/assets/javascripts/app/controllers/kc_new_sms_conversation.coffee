# KC: Agent page for initiating a new SMS conversation.
#
# Adds "New SMS" to the "+" dropdown in the top nav bar.
# Provides a form to search Zammad users by phone, enter a phone number,
# compose a message, and send it — creating a ticket + outbound SMS.

class KcNewSmsConversation extends App.ControllerPermanent
  @requiredPermission: ['ticket.agent']

  constructor: (params) ->
    super
    @authenticateCheckRedirect()

    App.TaskManager.execute(
      key:        'KcNewSmsConversation'
      controller: 'KcNewSmsConversationContent'
      params:     params
      show:       true
      persistent: true
    )

class App.KcNewSmsConversationContent extends App.Controller
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

    @html App.view('kc_new_sms_conversation/index')(
      groups:         groups
      defaultGroupId: defaultGroupId
    )

    @searchTimer = null
    @recipientResults = @el.find('.js-recipientResults')
    @loadChannels()

    # Close dropdown when clicking outside
    @outsideClickHandler = (e) =>
      return if $(e.target).closest('.js-recipientResults, .js-recipientSearch').length
      @recipientResults.hide().empty()
    $(document).on('click.kcSmsRecipient', @outsideClickHandler)

  release: ->
    clearTimeout(@searchTimer) if @searchTimer
    $(document).off('click.kcSmsRecipient')
    super

  loadChannels: ->
    @ajax(
      id:   'kc-sms-channels'
      type: 'GET'
      url:  "#{App.Config.get('api_path')}/kc/conversations/sms_channels"
      success: (data) =>
        select = @el.find('.js-fromNumber')
        select.empty()
        channels = data.channels || []
        defaultId = (data.default_channel_id || '').toString()
        for ch in channels
          label = ch.phone_number || "Channel #{ch.id}"
          option = $('<option>').val(ch.id).text(label)
          if defaultId && ch.id.toString() is defaultId
            option.prop('selected', true)
          select.append(option)
        if channels.length is 0
          select.append($('<option>').val('').text('No channels available'))
      error: =>
        @el.find('.js-fromNumber').html('<option value="">Failed to load channels</option>')
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
      id:   'kc-sms-user-search'
      type: 'GET'
      url:  "#{App.Config.get('api_path')}/kc/conversations/sms_users?query=#{encodeURIComponent(query)}"
      success: (data) =>
        @renderRecipientResults(data.users || [])
      error: =>
        @recipientResults.hide().empty()
    )

  # Normalize a phone number to E.164 format (+1XXXXXXXXXX for US numbers).
  # Strips non-digit characters (except leading +), then ensures +1 prefix.
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
      # Build a separate entry for each available number so the agent can pick
      numbers = []
      numbers.push({ label: 'phone', value: user.phone })  if user.phone
      numbers.push({ label: 'mobile', value: user.mobile }) if user.mobile and user.mobile isnt user.phone
      # Fallback: if somehow both are blank (shouldn't happen), skip
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
      normalized = @normalizePhone(rawPhone)
      @addRecipient(normalized, el.data('id'), el.data('name'))
      @recipientResults.hide().empty()
    )

  # Split the phone field into normalized, de-duplicated E.164 numbers.
  # Several numbers (comma / semicolon / newline separated) make a group text.
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

  # Picking a recipient from the search appends to the list instead of
  # replacing it, so a group text is built by searching several times.
  # The first recipient becomes the ticket customer.
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
    skipSend = $(e.currentTarget).is(':checked')
    if skipSend
      @el.find('.js-submit').text(App.i18n.translateInline('Create Ticket'))
    else
      @el.find('.js-submit').text(App.i18n.translateInline('Send SMS'))

  onSubmit: (e) ->
    e.preventDefault()

    rawPhone    = @el.find('.js-phoneNumber').val()?.trim()
    body        = @el.find('.js-body').val()?.trim()
    groupId     = @el.find('.js-group').val()
    customerId  = @el.find('.js-customerId').val()
    channelId   = @el.find('.js-fromNumber').val()
    skipSend    = @el.find('.js-skipSend').is(':checked')

    if !rawPhone || !body
      @showError(__('Phone number and message are required.'))
      return

    # Normalize every number to E.164 (+1XXXXXXXXXX); several = group text
    phoneNumbers = @parsePhones(rawPhone)
    if !phoneNumbers || phoneNumbers.length is 0
      @showError(__('Please enter a valid phone number.'))
      return
    if phoneNumbers.length > 10
      @showError(__('A group text can have at most 10 recipients.'))
      return
    phoneNumber = phoneNumbers[0]
    # Update the field so the user sees the corrected format
    @el.find('.js-phoneNumber').val(phoneNumbers.join(', '))

    @hideError()
    @el.find('.js-submit').prop('disabled', true)
    @el.find('.js-loading').show()
    loadingText = if skipSend then App.i18n.translateInline('Creating ticket...') else App.i18n.translateInline('Sending...')
    @el.find('.js-loadingText').text(loadingText)

    @ajax(
      id:   'kc-new-sms-conversation'
      type: 'POST'
      url:  "#{App.Config.get('api_path')}/kc/conversations/sms"
      data: JSON.stringify(
        phone_number:  phoneNumber
        phone_numbers: phoneNumbers
        body:          body
        group_id:     groupId
        customer_id:  customerId
        channel_id:   channelId
        skip_send:    skipSend
      )
      contentType: 'application/json'
      success: (data) =>
        @el.find('.js-submit').prop('disabled', false)
        @el.find('.js-loading').hide()
        # Navigate to the created ticket
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

App.Config.set('kc/new_rcsms', KcNewSmsConversation, 'Routes')
App.Config.set('KcNewSms', { prio: 8004, parent: '#new', name: __('New SMS Message (RingCentral)'), translate: true, target: '#kc/new_rcsms', permission: ['ticket.agent'] }, 'NavBarRight')
