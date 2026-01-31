# KC: Agent page for initiating a new Teams chat conversation.
#
# Adds "New Teams Message" to the "+" dropdown in the top nav bar.
# Provides a form to search the Azure AD directory for contacts,
# compose a message, and send it — creating a ticket + Teams chat message.

class KcNewTeamsConversation extends App.ControllerPermanent
  @requiredPermission: ['ticket.agent']

  constructor: (params) ->
    super
    @authenticateCheckRedirect()

    App.TaskManager.execute(
      key:        'KcNewTeamsConversation'
      controller: 'KcNewTeamsConversationContent'
      params:     params
      show:       true
      persistent: true
    )

class App.KcNewTeamsConversationContent extends App.Controller
  events:
    'submit .js-teamsForm':      'onSubmit'
    'input .js-contactSearch':   'onContactSearch'
    'click .js-clearContact':    'onClearContact'

  constructor: ->
    super
    @render()

  render: ->
    groups = App.Group.all().filter (g) -> g.active
    defaultGroupId = groups[0]?.id

    @html App.view('kc_new_teams_conversation/index')(
      groups:         groups
      defaultGroupId: defaultGroupId
    )

    @searchTimer = null
    @contactResults = @el.find('.js-contactResults')
    @loadChannels()

  loadChannels: ->
    @ajax(
      id:   'kc-teams-channels'
      type: 'GET'
      url:  "#{App.Config.get('api_path')}/kc/conversations/teams_channels"
      success: (data) =>
        select = @el.find('.js-fromAccount')
        select.empty()
        channels = data.channels || []
        defaultId = (data.default_channel_id || '').toString()
        for ch in channels
          label = ch.label || "Channel #{ch.id}"
          option = $('<option>').val(ch.id).text(label)
          if defaultId && ch.id.toString() is defaultId
            option.prop('selected', true)
          select.append(option)
        if channels.length is 0
          select.append($('<option>').val('').text('No channels available'))
      error: =>
        @el.find('.js-fromAccount').html('<option value="">Failed to load channels</option>')
    )

  onContactSearch: (e) ->
    query = $(e.target).val().trim()
    if query.length < 2
      @contactResults.hide().empty()
      return

    clearTimeout(@searchTimer) if @searchTimer
    @searchTimer = setTimeout(=>
      @searchContacts(query)
    , 300)

  searchContacts: (query) ->
    @ajax(
      id:   'kc-teams-contact-search'
      type: 'GET'
      url:  "#{App.Config.get('api_path')}/kc/conversations/teams_contacts"
      data: { query: query }
      success: (data) =>
        @renderContactResults(data.contacts || [])
      error: =>
        @contactResults.hide().empty()
    )

  renderContactResults: (contacts) ->
    if contacts.length is 0
      @contactResults.hide().empty()
      return

    html = ''
    for contact in contacts
      name  = contact.display_name || ''
      email = contact.email || ''
      title = contact.job_title || ''
      entry = """
        <div class="js-selectContact" data-id="#{contact.id}" data-name="#{App.Utils.htmlEscape(name)}" data-email="#{App.Utils.htmlEscape(email)}"
             style="padding:8px 12px; cursor:pointer; border-bottom:1px solid #eee;">
          <strong>#{App.Utils.htmlEscape(name)}</strong>
      """
      if email
        entry += " <span class=\"text-muted\">#{App.Utils.htmlEscape(email)}</span>"
      if title
        entry += "<br><small class=\"text-muted\">#{App.Utils.htmlEscape(title)}</small>"
      entry += '</div>'
      html += entry

    @contactResults.html(html).show()

    @contactResults.find('.js-selectContact').on('click', (e) =>
      el = $(e.currentTarget)
      @selectContact(el.data('id'), el.data('name'), el.data('email'))
    )

  selectContact: (id, name, email) ->
    @el.find('.js-teamsUserId').val(id)
    @el.find('.js-displayName').val(name)
    @el.find('.js-email').val(email || '')
    @el.find('.js-contactName').text(name)
    @el.find('.js-contactEmail').text(if email then " (#{email})" else '')
    @el.find('.js-selectedContact').show()
    @el.find('.js-contactSearch').val('').prop('disabled', true)
    @contactResults.hide().empty()

  onClearContact: (e) ->
    e.preventDefault()
    @el.find('.js-teamsUserId').val('')
    @el.find('.js-displayName').val('')
    @el.find('.js-email').val('')
    @el.find('.js-selectedContact').hide()
    @el.find('.js-contactSearch').val('').prop('disabled', false).focus()

  onSubmit: (e) ->
    e.preventDefault()

    teamsUserId = @el.find('.js-teamsUserId').val()?.trim()
    displayName = @el.find('.js-displayName').val()?.trim()
    email       = @el.find('.js-email').val()?.trim()
    body        = @el.find('.js-body').val()?.trim()
    groupId     = @el.find('.js-group').val()
    channelId   = @el.find('.js-fromAccount').val()

    if !teamsUserId || !displayName
      @showError('Please select a Teams contact first.')
      return

    if !body
      @showError('Message is required.')
      return

    @hideError()
    @el.find('.js-submit').prop('disabled', true)
    @el.find('.js-loading').show()

    @ajax(
      id:   'kc-new-teams-conversation'
      type: 'POST'
      url:  "#{App.Config.get('api_path')}/kc/conversations/teams"
      data: JSON.stringify(
        teams_user_id: teamsUserId
        display_name:  displayName
        email:         email
        body:          body
        group_id:      groupId
        channel_id:    channelId
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
          msg = JSON.parse(xhr.responseText)?.error || 'Failed to send Teams message'
        catch
          msg = 'Failed to send Teams message'
        @showError(msg)
    )

  showError: (msg) ->
    @el.find('.js-error').text(msg).show()

  hideError: ->
    @el.find('.js-error').hide()

App.Config.set('kc/new_teams', KcNewTeamsConversation, 'Routes')
App.Config.set('KcNewTeams', { prio: 8005, parent: '#new', name: __('New Teams Message'), translate: true, target: '#kc/new_teams', permission: ['ticket.agent'] }, 'NavBarRight')
