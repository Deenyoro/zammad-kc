# KC: Admin page for Microsoft Teams Chat channel management.
# Registered under KC Extensions > Teams Chat.
#
# Provides:
#   - List of connected Teams Chat accounts
#   - Add account via OAuth flow (client_id, secret, tenant, group)
#   - Edit account (group, thread window)
#   - Enable / Disable / Delete accounts

class KcTeamsChat extends App.ControllerSubContent
  @requiredPermission: 'admin'
  header: __('Teams Chat')

  events:
    'click .js-new':           'addAccount'
    'click .js-editAccount':   'editAccount'
    'click .js-deleteAccount': 'deleteAccount'
    'click .js-enableAccount': 'enableAccount'
    'click .js-disableAccount':'disableAccount'

  constructor: ->
    super
    @load()

  load: =>
    @startLoading()
    @ajax(
      id:   'kc_teams_chat_channels'
      type: 'GET'
      url:  "#{@apiPath}/kc/teams_chat_channels"
      success: (data) =>
        @stopLoading()
        App.Collection.loadAssets(data.assets)
        @channelIds = data.channel_ids || []
        @render()
      error: (xhr) =>
        @stopLoading()
        @html '<div class="alert alert--danger">Failed to load Teams Chat channels.</div>'
    )

  render: =>
    channels = []
    for id in @channelIds
      channel = App.Channel.find(id)
      if channel
        channels.push(channel)

    @html App.view('kc_teams_chat/index')(
      channels: channels
    )

  addAccount: (e) =>
    e.preventDefault()
    new KcTeamsChatAccountAdd(
      container: @el.closest('.content')
      callback:  @load
    )

  editAccount: (e) =>
    e.preventDefault()
    id = $(e.currentTarget).closest('[data-id]').data('id')
    channel = App.Channel.find(id)
    return if !channel

    new KcTeamsChatAccountEdit(
      container: @el.closest('.content')
      channel:   channel
      callback:  @load
    )

  deleteAccount: (e) =>
    e.preventDefault()
    id = $(e.currentTarget).closest('[data-id]').data('id')

    new App.ControllerConfirm(
      message: __('Are you sure you want to delete this Teams Chat account?')
      callback: =>
        @ajax(
          id:   "kc_teams_chat_delete_#{id}"
          type: 'DELETE'
          url:  "#{@apiPath}/kc/teams_chat_channels/#{id}"
          success: =>
            @load()
          error: (xhr) =>
            @notify(
              type: 'error'
              msg:  __('Failed to delete account.')
            )
        )
      container: @el.closest('.content')
    )

  enableAccount: (e) =>
    e.preventDefault()
    id = $(e.currentTarget).closest('[data-id]').data('id')
    @ajax(
      id:   "kc_teams_chat_enable_#{id}"
      type: 'POST'
      url:  "#{@apiPath}/kc/teams_chat_channels/#{id}/enable"
      success: =>
        @load()
      error: =>
        @notify(type: 'error', msg: __('Failed to enable account.'))
    )

  disableAccount: (e) =>
    e.preventDefault()
    id = $(e.currentTarget).closest('[data-id]').data('id')
    @ajax(
      id:   "kc_teams_chat_disable_#{id}"
      type: 'POST'
      url:  "#{@apiPath}/kc/teams_chat_channels/#{id}/disable"
      success: =>
        @load()
      error: =>
        @notify(type: 'error', msg: __('Failed to disable account.'))
    )


# ---------------------------------------------------------------------------
# Add account modal — collects Azure app credentials and initiates OAuth
# ---------------------------------------------------------------------------
class KcTeamsChatAccountAdd extends App.ControllerModal
  head: __('Add Teams Chat Account')
  buttonSubmit: __('Connect')
  buttonCancel: true

  content: ->
    groups = App.Group.all()
    App.view('kc_teams_chat/account_add')(
      groups: groups
    )

  onSubmit: (e) =>
    @formDisable(e)

    params =
      client_id:           @$('[name=client_id]').val()
      client_secret:       @$('[name=client_secret]').val()
      tenant_id:           @$('[name=tenant_id]').val()
      group_id:            @$('[name=group_id]').val()
      thread_window_hours: @$('[name=thread_window_hours]').val()

    if !params.client_id || !params.client_secret || !params.tenant_id
      @formEnable(e)
      @showAlert(__('Please fill in all required fields.'))
      return

    @ajax(
      id:   'kc_teams_chat_authorize'
      type: 'GET'
      url:  "#{@apiPath}/kc/teams_chat_channels/authorize"
      data: params
      success: (data) =>
        if data.authorize_url
          # Open Microsoft login in a new window
          window.open(data.authorize_url, '_blank', 'width=600,height=700')
          @close()
          @callback() if @callback

        else
          @formEnable(e)
          @showAlert(__('Failed to initiate OAuth flow.'))
      error: (xhr) =>
        @formEnable(e)
        data = xhr.responseJSON || {}
        @showAlert(data.error || __('Failed to connect.'))
    )


# ---------------------------------------------------------------------------
# Edit account modal — update group and thread window
# ---------------------------------------------------------------------------
class KcTeamsChatAccountEdit extends App.ControllerModal
  head: __('Edit Teams Chat Account')
  buttonSubmit: __('Save')
  buttonCancel: true

  content: ->
    groups = App.Group.all()
    options = @channel.options || {}
    App.view('kc_teams_chat/account_edit')(
      channel: @channel
      options: options
      groups:  groups
    )

  onSubmit: (e) =>
    @formDisable(e)

    params =
      group_id:            @$('[name=group_id]').val()
      thread_window_hours: @$('[name=thread_window_hours]').val()

    @ajax(
      id:   "kc_teams_chat_update_#{@channel.id}"
      type: 'PUT'
      url:  "#{@apiPath}/kc/teams_chat_channels/#{@channel.id}"
      data: JSON.stringify(params)
      contentType: 'application/json'
      success: =>
        @close()
        @callback() if @callback
      error: (xhr) =>
        @formEnable(e)
        data = xhr.responseJSON || {}
        @showAlert(data.error || __('Failed to save.'))
    )


# ---------------------------------------------------------------------------
# Register in admin navigation under KC Extensions
# ---------------------------------------------------------------------------
App.Config.set('KcTeamsChat', {
  prio:       2000
  name:       __('Teams Chat')
  parent:     '#kc_extensions'
  target:     '#kc_extensions/kc_teams_chat'
  controller: KcTeamsChat
  permission: ['admin']
}, 'NavBarAdmin')
