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
    'click .js-new':            'addAccount'
    'click .js-editAccount':    'editAccount'
    'click .js-deleteAccount':  'deleteAccount'
    'click .js-enableAccount':  'enableAccount'
    'click .js-disableAccount': 'disableAccount'
    'click .js-syncDirectory':      'syncDirectory'
    'click .js-reauthenticate':     'reauthenticateAccount'
    'click .js-saveSettings':   'saveSettings'

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
      settings:
        ticket_title_template:      App.Setting.get('kc_teams_chat_ticket_title_template') ? 'Teams Message from {user_name}'
        thread_window_hours:        App.Setting.get('kc_teams_chat_thread_window_hours') ? 24
        active_lookback_hours:      App.Setting.get('kc_teams_chat_active_lookback_hours') ? 2
        discovery_interval_minutes: App.Setting.get('kc_teams_chat_discovery_interval_minutes') ? 2
        deactivate_stale:           App.Setting.get('kc_teams_directory_deactivate_stale') ? false
        sync_phone:                 App.Setting.get('kc_teams_directory_sync_phone') ? false
        sync_job_title:             App.Setting.get('kc_teams_directory_sync_job_title') ? false
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
      container:     @el.closest('.content')
      channel:       channel
      organizations: App.Organization.all()
      callback:      @load
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

  syncDirectory: (e) =>
    e.preventDefault()
    id = $(e.currentTarget).closest('[data-id]').data('id')
    btn = $(e.currentTarget)
    btn.prop('disabled', true).text(App.i18n.translateInline('Syncing…'))
    @ajax(
      id:   "kc_teams_chat_sync_#{id}"
      type: 'POST'
      url:  "#{@apiPath}/kc/teams_chat_channels/#{id}/sync_directory"
      success: =>
        @notify(type: 'success', msg: __('Directory sync started. Refresh to see results.'))
        btn.prop('disabled', false).text(App.i18n.translateInline('Sync Now'))
      error: =>
        @notify(type: 'error', msg: __('Failed to start directory sync.'))
        btn.prop('disabled', false).text(App.i18n.translateInline('Sync Now'))
    )

  reauthenticateAccount: (e) =>
    e.preventDefault()
    id = $(e.currentTarget).closest('[data-id]').data('id')
    @ajax(
      id:   "kc_teams_chat_reauth_#{id}"
      type: 'POST'
      url:  "#{@apiPath}/kc/teams_chat_channels/#{id}/reauthenticate"
      success: (data) =>
        window.location.href = data.authorize_url
      error: (xhr) =>
        data = xhr.responseJSON || {}
        @notify(type: 'error', msg: data.error || __('Failed to start reauthentication.'))
    )

  saveSettings: (e) =>
    e.preventDefault()
    form = $(e.currentTarget).closest('.kc-teams-settings')

    settings =
      kc_teams_chat_ticket_title_template:      form.find('[name=ticket_title_template]').val() || 'Teams Message from {user_name}'
      kc_teams_chat_thread_window_hours:        parseInt(form.find('[name=thread_window_hours]').val()) || 24
      kc_teams_chat_active_lookback_hours:      parseInt(form.find('[name=active_lookback_hours]').val()) || 2
      kc_teams_chat_discovery_interval_minutes: parseInt(form.find('[name=discovery_interval_minutes]').val()) || 2
      kc_teams_directory_deactivate_stale:      form.find('[name=deactivate_stale]').is(':checked')
      kc_teams_directory_sync_phone:            form.find('[name=sync_phone]').is(':checked')
      kc_teams_directory_sync_job_title:        form.find('[name=sync_job_title]').is(':checked')

    pending = Object.keys(settings).length
    failed  = false

    for name, value of settings
      do (name, value) =>
        App.Setting.set(name, value,
          done: =>
            pending -= 1
            if pending is 0 && !failed
              @notify(type: 'success', msg: __('Settings saved.'))
          fail: =>
            failed = true
            @notify(type: 'error', msg: __('Failed to save settings.'))
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

    params = @formParams()

    if !params.client_id || !params.client_secret || !params.tenant_id
      @formEnable(e)
      @showAlert(__('Please fill in all required fields.'))
      return

    # POST credentials to server (never in URL/query string).
    # Server stores them in session and returns the Microsoft login URL.
    # Then we do a full-page GET redirect to that URL.
    @ajax(
      id:          'kc_teams_chat_authorize'
      type:        'POST'
      url:         "#{@apiPath}/kc/teams_chat_channels/authorize"
      data:        JSON.stringify(params)
      contentType: 'application/json'
      success: (data) =>
        window.location.href = data.authorize_url
      error: (xhr) =>
        @formEnable(e)
        data = xhr.responseJSON || {}
        @showAlert(data.error || __('Failed to start authorization.'))
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
    organizations = @organizations || App.Organization.all()
    options = @channel.options || {}
    App.view('kc_teams_chat/account_edit')(
      channel:       @channel
      options:       options
      groups:        groups
      organizations: organizations
    )

  onSubmit: (e) =>
    @formDisable(e)

    params = @formParams()
    # Checkbox not included in formParams when unchecked — set explicitly
    params.directory_sync = @el.find('[name=directory_sync]').is(':checked')

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
