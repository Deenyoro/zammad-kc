# KC: Admin page for RingCentral SMS channel management.
# Registered under KC Extensions > RingCentral SMS.
#
# Provides:
#   - List of connected RingCentral SMS accounts
#   - Add account via OAuth flow (client_id, secret, group)
#   - Edit account (group, thread window)
#   - Enable / Disable / Delete accounts
#   - Global settings (ticket title template, thread window, poll interval)

class KcRingcentralSms extends App.ControllerSubContent
  @requiredPermission: 'admin'
  header: __('RingCentral SMS')

  events:
    'click .js-new':            'addAccount'
    'click .js-editAccount':    'editAccount'
    'click .js-deleteAccount':  'deleteAccount'
    'click .js-enableAccount':  'enableAccount'
    'click .js-disableAccount': 'disableAccount'
    'click .js-saveSettings':   'saveSettings'

  constructor: ->
    super
    @load()

  load: =>
    @startLoading()
    @ajax(
      id:   'kc_ringcentral_sms_channels'
      type: 'GET'
      url:  "#{@apiPath}/kc/ringcentral_sms_channels"
      success: (data) =>
        @stopLoading()
        App.Collection.loadAssets(data.assets)
        @channelIds = data.channel_ids || []
        @render()
      error: (xhr) =>
        @stopLoading()
        @html '<div class="alert alert--danger">Failed to load RingCentral SMS channels.</div>'
    )

  render: =>
    channels = []
    for id in @channelIds
      channel = App.Channel.find(id)
      if channel
        channels.push(channel)

    @html App.view('kc_ringcentral_sms/index')(
      channels: channels
      settings:
        ticket_title_template: App.Setting.get('kc_ringcentral_sms_ticket_title_template') ? 'SMS from {phone}'
        thread_window_hours:   App.Setting.get('kc_ringcentral_sms_thread_window_hours') ? 24
        poll_interval_seconds: App.Setting.get('kc_ringcentral_sms_poll_interval_seconds') ? 60
    )

  addAccount: (e) =>
    e.preventDefault()
    new KcRingcentralSmsAccountAdd(
      container: @el.closest('.content')
      callback:  @load
    )

  editAccount: (e) =>
    e.preventDefault()
    id = $(e.currentTarget).closest('[data-id]').data('id')
    channel = App.Channel.find(id)
    return if !channel

    new KcRingcentralSmsAccountEdit(
      container: @el.closest('.content')
      channel:   channel
      callback:  @load
    )

  deleteAccount: (e) =>
    e.preventDefault()
    id = $(e.currentTarget).closest('[data-id]').data('id')

    new App.ControllerConfirm(
      message: __('Are you sure you want to delete this RingCentral SMS account?')
      callback: =>
        @ajax(
          id:   "kc_ringcentral_sms_delete_#{id}"
          type: 'DELETE'
          url:  "#{@apiPath}/kc/ringcentral_sms_channels/#{id}"
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
      id:   "kc_ringcentral_sms_enable_#{id}"
      type: 'POST'
      url:  "#{@apiPath}/kc/ringcentral_sms_channels/#{id}/enable"
      success: =>
        @load()
      error: =>
        @notify(type: 'error', msg: __('Failed to enable account.'))
    )

  disableAccount: (e) =>
    e.preventDefault()
    id = $(e.currentTarget).closest('[data-id]').data('id')
    @ajax(
      id:   "kc_ringcentral_sms_disable_#{id}"
      type: 'POST'
      url:  "#{@apiPath}/kc/ringcentral_sms_channels/#{id}/disable"
      success: =>
        @load()
      error: =>
        @notify(type: 'error', msg: __('Failed to disable account.'))
    )

  saveSettings: (e) =>
    e.preventDefault()
    form = $(e.currentTarget).closest('.kc-ringcentral-settings')

    settings =
      kc_ringcentral_sms_ticket_title_template: form.find('[name=ticket_title_template]').val() || 'SMS from {phone}'
      kc_ringcentral_sms_thread_window_hours:   parseInt(form.find('[name=thread_window_hours]').val()) || 24
      kc_ringcentral_sms_poll_interval_seconds: parseInt(form.find('[name=poll_interval_seconds]').val()) || 60

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
# Add account modal — collects RingCentral app credentials and initiates OAuth
# ---------------------------------------------------------------------------
class KcRingcentralSmsAccountAdd extends App.ControllerModal
  head: __('Add RingCentral SMS Account')
  buttonSubmit: __('Connect')
  buttonCancel: true

  content: ->
    groups = App.Group.all()
    App.view('kc_ringcentral_sms/account_add')(
      groups: groups
    )

  onSubmit: (e) =>
    @formDisable(e)

    params = @formParams()

    if !params.client_id || !params.client_secret
      @formEnable(e)
      @showAlert(__('Please fill in all required fields.'))
      return

    # POST credentials to server (never in URL/query string).
    @ajax(
      id:          'kc_ringcentral_sms_authorize'
      type:        'POST'
      url:         "#{@apiPath}/kc/ringcentral_sms_channels/authorize"
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
class KcRingcentralSmsAccountEdit extends App.ControllerModal
  head: __('Edit RingCentral SMS Account')
  buttonSubmit: __('Save')
  buttonCancel: true

  content: ->
    groups = App.Group.all()
    options = @channel.options || {}
    App.view('kc_ringcentral_sms/account_edit')(
      channel: @channel
      options: options
      groups:  groups
    )

  onSubmit: (e) =>
    @formDisable(e)

    params = @formParams()

    @ajax(
      id:   "kc_ringcentral_sms_update_#{@channel.id}"
      type: 'PUT'
      url:  "#{@apiPath}/kc/ringcentral_sms_channels/#{@channel.id}"
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
App.Config.set('KcRingcentralSms', {
  prio:       2100
  name:       __('RingCentral SMS')
  parent:     '#kc_extensions'
  target:     '#kc_extensions/kc_ringcentral_sms'
  controller: KcRingcentralSms
  permission: ['admin']
}, 'NavBarAdmin')
