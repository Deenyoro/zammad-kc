# KC: Agent page for initiating a new SMS conversation.
#
# Adds "New SMS" to the "+" dropdown in the top nav bar.
# Provides a form to search Zammad users by phone, enter a phone number,
# compose a message, and send it — creating a ticket + outbound SMS.
#
# Every new SMS is a draft tab in the taskbar (like "New Ticket"), see
# App.KcConversationDraft: the form is kept while the agent works elsewhere,
# survives a reload, and the tab closes once the SMS has been sent.

class App.KcNewSmsConversationContent extends App.Controller
  @include App.KcConversationDraft

  draftRoute: 'kc/new_rcsms'
  draftLabel: __('SMS')
  draftForm:  '.js-smsForm'

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
      uid:            @taskKey
    )

    @searchTimer = null
    @recipientResults = @el.find('.js-recipientResults')
    @draftRestore()
    @loadChannels()

    # Close dropdown when clicking outside (namespaced per draft, several
    # drafts can be open at once)
    @outsideClickEvent = "click.kcSmsRecipient#{@controllerId}"
    @outsideClickHandler = (e) =>
      return if $(e.target).closest('.js-recipientResults, .js-recipientSearch').length
      @recipientResults.hide().empty()
    $(document).on(@outsideClickEvent, @outsideClickHandler)

  draftCollect: ->
    phone_number: @el.find('.js-phoneNumber').val() || ''
    customer_id:  @el.find('.js-customerId').val() || ''
    channel_id:   @el.find('.js-fromNumber').val() || @draftChannelId || ''
    group_id:     @el.find('.js-group').val() || ''
    body:         @el.find('.js-body').val() || ''
    skip_send:    @el.find('.js-skipSend').is(':checked')

  draftApply: (state) ->
    @el.find('.js-phoneNumber').val(state.phone_number || '')
    @el.find('.js-customerId').val(state.customer_id || '')
    @el.find('.js-clearRecipient').toggle(!!state.phone_number)
    if state.group_id && @el.find(".js-group option[value='#{state.group_id}']").get(0)
      @el.find('.js-group').val(state.group_id)
    @el.find('.js-body').val(state.body || '')
    @el.find('.js-skipSend').prop('checked', !!state.skip_send)
    @updateSubmitLabel()
    @updateRecipientHint()

    # the sender options arrive later (loadChannels)
    @draftChannelId = state.channel_id

  draftDetail: (state) ->
    (state.phone_number || '').trim()

  draftHasContent: (state) ->
    !!((state.phone_number || '').trim() || (state.body || '').trim())

  release: ->
    clearTimeout(@searchTimer) if @searchTimer
    $(document).off(@outsideClickEvent) if @outsideClickEvent
    super

  loadChannels: ->
    @ajax(
      id:   "kc-sms-channels-#{@taskKey}"
      type: 'GET'
      url:  "#{App.Config.get('api_path')}/kc/conversations/sms_channels"
      success: (data) =>
        select = @el.find('.js-fromNumber')
        select.empty()
        channels = data.channels || []
        # a restored draft keeps its sender, if it still exists
        defaultId = (data.default_channel_id || '').toString()
        draftId   = (@draftChannelId || '').toString()
        if draftId && _.find(channels, (ch) -> ch.id.toString() is draftId)
          defaultId = draftId
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
      id:   "kc-sms-user-search-#{@taskKey}"
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
    @draftSave()

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
    @draftSave()

  onPhoneInput: ->
    @updateRecipientHint()

  onSkipSendToggle: ->
    @updateSubmitLabel()

  updateSubmitLabel: ->
    if @el.find('.js-skipSend').is(':checked')
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
      id:   "kc-new-sms-conversation-#{@taskKey}"
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
        # Close the draft tab and navigate to the created ticket
        @draftClose()
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

KcNewSmsConversation = App.KcConversationDraftRouter('kc/new_rcsms', 'KcNewSmsScreen', 'KcNewSmsConversationContent')
App.Config.set('kc/new_rcsms', KcNewSmsConversation, 'Routes')
App.Config.set('kc/new_rcsms/id/:id', KcNewSmsConversation, 'Routes')
App.Config.set('KcNewSms', { prio: 8004, parent: '#new', name: __('New SMS Message (RingCentral)'), translate: true, target: '#kc/new_rcsms', permission: ['ticket.agent'] }, 'NavBarRight')
