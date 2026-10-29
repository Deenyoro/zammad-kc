# KC: Agent page for initiating a new Teams chat conversation.
#
# Adds "New Teams Message" to the "+" dropdown in the top nav bar.
# Provides a form to search the Azure AD directory for contacts,
# compose a message, and send it — creating a ticket + Teams chat message.
#
# Every new message is a draft tab in the taskbar (like "New Ticket"), see
# App.KcConversationDraft.

class App.KcNewTeamsConversationContent extends App.Controller
  @include App.KcConversationDraft

  draftRoute: 'kc/new_teams'
  draftLabel: __('Teams Message')
  draftForm:  '.js-teamsForm'

  events:
    'submit .js-teamsForm':      'onSubmit'
    'input .js-contactSearch':   'onContactSearch'
    'click .js-clearContact':    'onClearContact'
    'change .js-skipSend':       'onSkipSendToggle'

  constructor: ->
    super
    @render()

  render: ->
    groups = App.Group.all().filter (g) -> g.active
    defaultGroupId = groups[0]?.id

    @html App.view('kc_new_teams_conversation/index')(
      groups:         groups
      defaultGroupId: defaultGroupId
      uid:            @taskKey
    )

    @searchTimer = null
    @contactResults = @el.find('.js-contactResults')
    @draftRestore()
    @loadChannels()

  draftCollect: ->
    teams_user_id: @el.find('.js-teamsUserId').val() || ''
    display_name:  @el.find('.js-displayName').val() || ''
    email:         @el.find('.js-email').val() || ''
    channel_id:    @el.find('.js-fromAccount').val() || @draftChannelId || ''
    group_id:      @el.find('.js-group').val() || ''
    body:          @el.find('.js-body').val() || ''
    skip_send:     @el.find('.js-skipSend').is(':checked')

  draftApply: (state) ->
    if state.teams_user_id
      @selectContact(state.teams_user_id, state.display_name || '', state.email || '')
    if state.group_id && @el.find(".js-group option[value='#{state.group_id}']").get(0)
      @el.find('.js-group').val(state.group_id)
    @el.find('.js-body').val(state.body || '')
    @el.find('.js-skipSend').prop('checked', !!state.skip_send)
    @updateSubmitLabel()

    # the sender options arrive later (loadChannels)
    @draftChannelId = state.channel_id

  draftDetail: (state) ->
    (state.display_name || '').trim()

  draftHasContent: (state) ->
    !!(state.teams_user_id || (state.body || '').trim())

  release: ->
    clearTimeout(@searchTimer) if @searchTimer
    super

  loadChannels: ->
    @ajax(
      id:   "kc-teams-channels-#{@taskKey}"
      type: 'GET'
      url:  "#{App.Config.get('api_path')}/kc/conversations/teams_channels"
      success: (data) =>
        select = @el.find('.js-fromAccount')
        select.empty()
        channels = data.channels || []
        # a restored draft keeps its sender, if it still exists
        defaultId = (data.default_channel_id || '').toString()
        draftId   = (@draftChannelId || '').toString()
        if draftId && _.find(channels, (ch) -> ch.id.toString() is draftId)
          defaultId = draftId
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
      id:   "kc-teams-contact-search-#{@taskKey}"
      type: 'GET'
      url:  "#{App.Config.get('api_path')}/kc/conversations/teams_contacts?query=#{encodeURIComponent(query)}&channel_id=#{encodeURIComponent(@el.find('.js-fromAccount').val() || '')}"
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
             style="padding:8px 12px; cursor:pointer; border-bottom:1px solid var(--border);">
          <strong>#{App.Utils.htmlEscape(name)}</strong>
      """
      if email
        entry += " <span style=\"opacity:.7;\">#{App.Utils.htmlEscape(email)}</span>"
      if title
        entry += "<br><small style=\"opacity:.7;\">#{App.Utils.htmlEscape(title)}</small>"
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
    @draftSave()

  onClearContact: (e) ->
    e.preventDefault()
    @el.find('.js-teamsUserId').val('')
    @el.find('.js-displayName').val('')
    @el.find('.js-email').val('')
    @el.find('.js-selectedContact').hide()
    @el.find('.js-contactSearch').val('').prop('disabled', false).focus()
    @draftSave()

  onSubmit: (e) ->
    e.preventDefault()

    teamsUserId = @el.find('.js-teamsUserId').val()?.trim()
    displayName = @el.find('.js-displayName').val()?.trim()
    email       = @el.find('.js-email').val()?.trim()
    body        = @el.find('.js-body').val()?.trim()
    groupId     = @el.find('.js-group').val()
    channelId   = @el.find('.js-fromAccount').val()
    skipSend    = @el.find('.js-skipSend').is(':checked')

    if !teamsUserId || !displayName
      @showError(__('Please select a Teams contact first.'))
      return

    if !body
      @showError(__('Message is required.'))
      return

    @hideError()
    @el.find('.js-submit').prop('disabled', true)
    @el.find('.js-loading').show()

    @ajax(
      id:   "kc-new-teams-conversation-#{@taskKey}"
      type: 'POST'
      url:  "#{App.Config.get('api_path')}/kc/conversations/teams"
      data: JSON.stringify(
        teams_user_id: teamsUserId
        display_name:  displayName
        email:         email
        body:          body
        group_id:      groupId
        channel_id:    channelId
        skip_send:     skipSend
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
          msg = JSON.parse(xhr.responseText)?.error || __('Failed to send Teams message')
        catch
          msg = __('Failed to send Teams message')
        @showError(msg)
    )

  onSkipSendToggle: ->
    @updateSubmitLabel()

  updateSubmitLabel: ->
    if @el.find('.js-skipSend').is(':checked')
      @el.find('.js-submit').text(App.i18n.translateInline('Create Ticket'))
    else
      @el.find('.js-submit').text(App.i18n.translateInline('Send Teams Message'))

  showError: (msg) ->
    @el.find('.js-error').text(msg).show()

  hideError: ->
    @el.find('.js-error').hide()

KcNewTeamsConversation = App.KcConversationDraftRouter('kc/new_teams', 'KcNewTeamsScreen', 'KcNewTeamsConversationContent')
App.Config.set('kc/new_teams', KcNewTeamsConversation, 'Routes')
App.Config.set('kc/new_teams/id/:id', KcNewTeamsConversation, 'Routes')
App.Config.set('KcNewTeams', { prio: 8005, parent: '#new', name: __('New Teams Message'), translate: true, target: '#kc/new_teams', permission: ['ticket.agent'] }, 'NavBarRight')
