# KC: Admin page for the FreePBX phone integration.
# Registered under KC Extensions > FreePBX.
#
# RingCentral rings first and owns texting; calls it does not answer forward
# to FreePBX where the team rings. This page connects Zammad to the KC PBX
# connector on the FreePBX host and configures what happens when the team
# misses a call there.

class KcFreepbx extends App.ControllerSubContent
  @requiredPermission: 'admin'
  header: __('FreePBX')

  events:
    'click .js-new':                    'addConnection'
    'click .js-editConnection':         'editConnection'
    'click .js-deleteConnection':       'deleteConnection'
    'click .js-enableConnection':       'enableConnection'
    'click .js-disableConnection':      'disableConnection'
    'click .js-testConnection':         'testConnection'
    'click .js-saveMissedCallSettings': 'saveMissedCallSettings'

  constructor: ->
    super
    @load()

  load: =>
    @startLoading()
    @ajax(
      id:   'kc_freepbx_channels'
      type: 'GET'
      url:  "#{@apiPath}/kc/freepbx_channels"
      success: (data) =>
        @stopLoading()
        App.Collection.loadAssets(data.assets)
        @channelIds       = data.channel_ids || []
        @availableNumbers = data.available_numbers || []
        @render()
      error: =>
        @stopLoading()
        @html '<div class="alert alert--danger">' + App.i18n.translateInline('Failed to load FreePBX connections.') + '</div>'
    )

  # App.Setting.get() throws when a setting is missing from the local
  # collection, which would abort render() and blank the page.
  setting: (name, fallback) ->
    try
      value = App.Setting.get(name)
      return fallback if !value?
      value
    catch
      fallback

  render: =>
    channels = []
    for id in @channelIds
      channel = App.Channel.find(id)
      channels.push(channel) if channel

    @html App.view('kc_freepbx/index')(
      channels: channels
      numbers:  @availableNumbers
      settings:
        missed_call_ticket:            @setting('kc_freepbx_missed_call_ticket', true)
        missed_call_ticket_title:      @setting('kc_freepbx_missed_call_ticket_title', 'Missed call from {phone}')
        missed_call_autoreply:         @setting('kc_freepbx_missed_call_autoreply', true)
        missed_call_autoreply_message: @setting('kc_freepbx_missed_call_autoreply_message', 'We are sorry for missing your call. A ticket has been created and our team will follow up with you shortly.')
        missed_call_autoreply_from:    String(@setting('kc_freepbx_missed_call_autoreply_from', '') or '')
        escalation_call_enabled:       @setting('kc_escalation_call_enabled', false)
    )

  addConnection: (e) =>
    e.preventDefault()
    new KcFreepbxConnectionAdd(container: @el.closest('.content'), callback: @load)

  editConnection: (e) =>
    e.preventDefault()
    id = $(e.currentTarget).closest('.action').data('id')
    channel = App.Channel.find(id)
    return if !channel
    new KcFreepbxConnectionEdit(container: @el.closest('.content'), channel: channel, callback: @load)

  testConnection: (e) =>
    e.preventDefault()
    button = $(e.currentTarget)
    id = button.closest('.action').data('id')
    button.prop('disabled', true).text(App.i18n.translateContent('Testing…'))
    @ajax(
      id:   'kc_freepbx_test'
      type: 'POST'
      url:  "#{@apiPath}/kc/freepbx_channels/#{id}/test"
      success: (data) =>
        button.prop('disabled', false).text(App.i18n.translateContent('Test'))
        if data.ok
          registered = data.registered ? 0
          total      = data.extension_count ? 0
          @notify(type: 'success', msg: App.i18n.translateContent('Connected. %s of %s extensions registered.', registered, total))
          @load()
        else
          @notify(type: 'error', msg: data.error || __('Could not reach the FreePBX connector.'))
      error: =>
        button.prop('disabled', false).text(App.i18n.translateContent('Test'))
        @notify(type: 'error', msg: __('Could not reach the FreePBX connector.'))
    )

  enableConnection: (e) =>
    @toggleConnection(e, 'enable')

  disableConnection: (e) =>
    @toggleConnection(e, 'disable')

  toggleConnection: (e, action) =>
    e.preventDefault()
    id = $(e.currentTarget).closest('.action').data('id')
    @ajax(
      id:   "kc_freepbx_#{action}"
      type: 'POST'
      url:  "#{@apiPath}/kc/freepbx_channels/#{id}/#{action}"
      success: => @load()
      error:   => @notify(type: 'error', msg: __('Failed to update the connection.'))
    )

  deleteConnection: (e) =>
    e.preventDefault()
    id = $(e.currentTarget).closest('.action').data('id')
    new App.ControllerConfirm(
      message:     __('Delete this FreePBX connection?')
      buttonClass: 'btn--danger'
      callback: =>
        @ajax(
          id:   'kc_freepbx_delete'
          type: 'DELETE'
          url:  "#{@apiPath}/kc/freepbx_channels/#{id}"
          success: => @load()
          error:   => @notify(type: 'error', msg: __('Failed to delete the connection.'))
        )
      container: @el.closest('.content')
    )

  saveMissedCallSettings: (e) =>
    e.preventDefault()
    form = $(e.currentTarget).closest('.page-content')

    settings =
      kc_freepbx_missed_call_ticket:            form.find('[name=missed_call_ticket]').is(':checked')
      kc_freepbx_missed_call_ticket_title:      form.find('[name=missed_call_ticket_title]').val() || 'Missed call from {phone}'
      kc_freepbx_missed_call_autoreply:         form.find('[name=missed_call_autoreply]').is(':checked')
      kc_freepbx_missed_call_autoreply_message: form.find('[name=missed_call_autoreply_message]').val() || ''
      kc_freepbx_missed_call_autoreply_from:    form.find('[name=missed_call_autoreply_from]').val() || ''
      kc_escalation_call_enabled:               form.find('[name=escalation_call_enabled]').is(':checked')

    pending = Object.keys(settings).length
    failed  = false

    for name, value of settings
      do (name, value) =>
        App.Setting.set(name, value,
          done: =>
            pending -= 1
            if pending is 0 && !failed
              @notify(type: 'success', msg: __('Missed call settings saved.'))
          fail: =>
            failed = true
            @notify(type: 'error', msg: __('Failed to save missed call settings.'))
        )


# ---------------------------------------------------------------------------
# Add / edit connection modals
# ---------------------------------------------------------------------------
class KcFreepbxConnectionAdd extends App.ControllerModal
  head: __('Add FreePBX Connection')
  buttonSubmit: __('Connect')
  buttonCancel: true

  content: ->
    App.view('kc_freepbx/connection_form')(
      channel: null
      groups:  App.Group.all()
    )

  onSubmit: (e) =>
    params = @formParam(e.target)
    if !params.base_url || !params.token
      @el.find('.alert').removeClass('hide').text(App.i18n.translateContent('Server URL and token are required.'))
      return
    @ajax(
      id:   'kc_freepbx_create'
      type: 'POST'
      url:  "#{App.Config.get('api_path')}/kc/freepbx_channels"
      data: JSON.stringify(params)
      contentType: 'application/json'
      success: =>
        @close()
        @options.callback?()
      error: (xhr) =>
        data = xhr.responseJSON || {}
        @el.find('.alert').removeClass('hide').text(data.error || App.i18n.translateContent('Failed to create the connection.'))
    )


class KcFreepbxConnectionEdit extends App.ControllerModal
  head: __('Edit FreePBX Connection')
  buttonSubmit: __('Save')
  buttonCancel: true

  content: ->
    App.view('kc_freepbx/connection_form')(
      channel: @options.channel
      groups:  App.Group.all()
    )

  onSubmit: (e) =>
    params = @formParam(e.target)
    @ajax(
      id:   'kc_freepbx_update'
      type: 'PUT'
      url:  "#{App.Config.get('api_path')}/kc/freepbx_channels/#{@options.channel.id}"
      data: JSON.stringify(params)
      contentType: 'application/json'
      success: =>
        @close()
        @options.callback?()
      error: (xhr) =>
        data = xhr.responseJSON || {}
        @el.find('.alert').removeClass('hide').text(data.error || App.i18n.translateContent('Failed to save the connection.'))
    )


# ---------------------------------------------------------------------------
# Register in admin navigation under KC Extensions
# ---------------------------------------------------------------------------
App.Config.set('KcFreepbx', {
  prio:       2150
  name:       __('FreePBX')
  parent:     '#kc_extensions'
  target:     '#kc_extensions/kc_freepbx'
  controller: KcFreepbx
  permission: ['admin']
}, 'NavBarAdmin')
