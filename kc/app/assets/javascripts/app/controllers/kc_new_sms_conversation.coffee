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
      url:  "#{App.Config.get('api_path')}/kc/conversations/sms_users"
      data: { query: query }
      success: (data) =>
        @renderRecipientResults(data.users || [])
      error: =>
        @recipientResults.hide().empty()
    )

  renderRecipientResults: (users) ->
    if users.length is 0
      @recipientResults.hide().empty()
      return

    html = ''
    for user in users
      phone = user.phone || user.mobile || ''
      name = user.name || ''
      html += """
        <div class="js-selectRecipient" data-id="#{user.id}" data-phone="#{App.Utils.htmlEscape(phone)}" data-name="#{App.Utils.htmlEscape(name)}"
             style="padding:8px 12px; cursor:pointer; border-bottom:1px solid #eee;">
          <strong>#{App.Utils.htmlEscape(name)}</strong>
          <span class="text-muted">#{App.Utils.htmlEscape(phone)}</span>
        </div>
      """

    @recipientResults.html(html).show()

    @recipientResults.find('.js-selectRecipient').on('click', (e) =>
      el = $(e.currentTarget)
      @el.find('.js-phoneNumber').val(el.data('phone'))
      @el.find('.js-customerId').val(el.data('id'))
      @el.find('.js-recipientSearch').val(el.data('name'))
      @recipientResults.hide().empty()
    )

  onClearRecipient: (e) ->
    e.preventDefault()
    @el.find('.js-phoneNumber').val('')
    @el.find('.js-customerId').val('')
    @el.find('.js-recipientSearch').val('')

  onSubmit: (e) ->
    e.preventDefault()

    phoneNumber = @el.find('.js-phoneNumber').val()?.trim()
    body        = @el.find('.js-body').val()?.trim()
    groupId     = @el.find('.js-group').val()
    customerId  = @el.find('.js-customerId').val()
    channelId   = @el.find('.js-fromNumber').val()

    if !phoneNumber || !body
      @showError('Phone number and message are required.')
      return

    @hideError()
    @el.find('.js-submit').prop('disabled', true)
    @el.find('.js-loading').show()

    @ajax(
      id:   'kc-new-sms-conversation'
      type: 'POST'
      url:  "#{App.Config.get('api_path')}/kc/conversations/sms"
      data: JSON.stringify(
        phone_number: phoneNumber
        body:         body
        group_id:     groupId
        customer_id:  customerId
        channel_id:   channelId
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
          msg = JSON.parse(xhr.responseText)?.error || 'Failed to send SMS'
        catch
          msg = 'Failed to send SMS'
        @showError(msg)
    )

  showError: (msg) ->
    @el.find('.js-error').text(msg).show()

  hideError: ->
    @el.find('.js-error').hide()

App.Config.set('kc/new_sms', KcNewSmsConversation, 'Routes')
App.Config.set('KcNewSms', { prio: 8004, parent: '#new', name: __('New SMS Message (RingCentral)'), translate: true, target: '#kc/new_sms', permission: ['ticket.agent'] }, 'NavBarRight')
