# KC: Admin page for RingCentral SMS channel management.
# Registered under KC Extensions > RingCentral SMS.
#
# Provides:
#   - List of connected RingCentral SMS accounts
#   - Add account via OAuth flow (client_id, secret, group)
#   - Edit account (group, thread window, phone number)
#   - Enable / Disable / Delete accounts
#   - Global settings (ticket title template, thread window, poll interval)
#   - Phone number selection page (post-OAuth)

class KcRingcentralSms extends App.ControllerSubContent
  @requiredPermission: 'admin'
  header: __('RingCentral SMS')

  events:
    'click .js-new':                    'addAccount'
    'click .js-editAccount':            'editAccount'
    'click .js-deleteAccount':          'deleteAccount'
    'click .js-enableAccount':          'enableAccount'
    'click .js-disableAccount':         'disableAccount'
    'click .js-reauthenticate':         'reauthenticateAccount'
    'click .js-saveSettings':           'saveSettings'
    'click .js-saveMissedCallSettings': 'saveMissedCallSettings'

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
        @html '<div class="alert alert--danger">' + App.i18n.translateInline('Failed to load RingCentral SMS channels.') + '</div>'
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
        ticket_title_template:        App.Setting.get('kc_ringcentral_sms_ticket_title_template') ? 'SMS from {phone}'
        thread_window_hours:          App.Setting.get('kc_ringcentral_sms_thread_window_hours') ? 24
        poll_interval_seconds:        App.Setting.get('kc_ringcentral_sms_poll_interval_seconds') ? 60
        missed_call_ticket:           App.Setting.get('kc_ringcentral_sms_missed_call_ticket') is true
        missed_call_ticket_title:     App.Setting.get('kc_ringcentral_sms_missed_call_ticket_title') ? 'Missed call from {phone}'
        missed_call_autoreply:        App.Setting.get('kc_ringcentral_sms_missed_call_autoreply') is true
        missed_call_autoreply_message: App.Setting.get('kc_ringcentral_sms_missed_call_autoreply_message') ? 'We are sorry for missing your call. A ticket has been created and our team will follow up with you shortly.'
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

  reauthenticateAccount: (e) =>
    e.preventDefault()
    id = $(e.currentTarget).closest('[data-id]').data('id')
    @ajax(
      id:   "kc_ringcentral_sms_reauth_#{id}"
      type: 'POST'
      url:  "#{@apiPath}/kc/ringcentral_sms_channels/#{id}/reauthenticate"
      success: (data) =>
        if data.authorize_url && data.authorize_url.match(/^https:\/\//)
          window.location.href = data.authorize_url
        else
          @notify(type: 'error', msg: __('Invalid authorization URL received.'))
      error: (xhr) =>
        data = xhr.responseJSON || {}
        @notify(type: 'error', msg: data.error || __('Failed to start reauthentication.'))
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

  saveMissedCallSettings: (e) =>
    e.preventDefault()
    form = $(e.currentTarget).closest('.page-content')

    settings =
      kc_ringcentral_sms_missed_call_ticket:           form.find('[name=missed_call_ticket]').is(':checked')
      kc_ringcentral_sms_missed_call_ticket_title:     form.find('[name=missed_call_ticket_title]').val() || 'Missed call from {phone}'
      kc_ringcentral_sms_missed_call_autoreply:        form.find('[name=missed_call_autoreply]').is(':checked')
      kc_ringcentral_sms_missed_call_autoreply_message: form.find('[name=missed_call_autoreply_message]').val() || 'We are sorry for missing your call. A ticket has been created and our team will follow up with you shortly.'

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
        if data.authorize_url && data.authorize_url.match(/^https:\/\//)
          window.location.href = data.authorize_url
        else
          @formEnable(e)
          @showAlert(__('Invalid authorization URL received.'))
      error: (xhr) =>
        @formEnable(e)
        data = xhr.responseJSON || {}
        @showAlert(App.Utils.htmlEscape(data.error) || __('Failed to start authorization.'))
    )


# ---------------------------------------------------------------------------
# Edit account modal — update group, thread window, and phone number
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
        @showAlert(App.Utils.htmlEscape(data.error) || __('Failed to save.'))
    )


# ---------------------------------------------------------------------------
# Phone number selection page — shown after OAuth callback
# ---------------------------------------------------------------------------
class KcRingcentralSmsPhoneSelect extends App.ControllerAppContent
  @requiredPermission: 'admin'

  constructor: ->
    super
    @title __('Select Phone Number')
    @fetch()

  fetch: =>
    @html '<div class="page-header"><h1>' + App.i18n.translateContent('Select Phone Number') + '</h1></div><div class="page-content"><div class="loading icon"></div></div>'
    @ajax(
      id:   'kc_ringcentral_sms_pending_setup'
      type: 'GET'
      url:  "#{@apiPath}/kc/ringcentral_sms_channels/pending_setup"
      success: (data) =>
        @availablePhones  = data.available_phones || []
        @userDisplayName  = data.user_display_name
        @userEmail        = data.user_email
        @render()
      error: (xhr) =>
        data = xhr.responseJSON || {}
        @html """
          <div class="page-header"><h1>#{App.i18n.translateContent('Select Phone Number')}</h1></div>
          <div class="page-content">
            <div class="alert alert--danger">#{App.Utils.htmlEscape(data.error || App.i18n.translateInline('No pending setup found. Please start the OAuth flow again.'))}</div>
            <p><a href="#kc_extensions/kc_ringcentral_sms">#{App.i18n.translateContent('Back to RingCentral SMS')}</a></p>
          </div>
        """
    )

  render: =>
    phoneOptions = ''
    for phone in @availablePhones
      label = phone.phone_number
      if phone.label
        label = "#{phone.phone_number} (#{phone.label})"
      else if phone.usage_type
        label = "#{phone.phone_number} (#{phone.usage_type})"
      phoneOptions += "<option value=\"#{App.Utils.htmlEscape(phone.phone_number)}\">#{App.Utils.htmlEscape(label)}</option>"

    accountInfo = App.Utils.htmlEscape(@userDisplayName || '')
    if @userEmail
      accountInfo += " &mdash; #{App.Utils.htmlEscape(@userEmail)}"

    @html """
      <div class="page-header"><h1>#{App.i18n.translateContent('Select Phone Number')}</h1></div>
      <div class="page-content">
        <div class="box box--message">
          <h2>#{App.i18n.translateContent('RingCentral Account Connected')}</h2>
          <p class="text-muted">#{accountInfo}</p>
          <p>#{App.i18n.translateContent('Please select the phone number you want to use for SMS messaging:')}</p>
          <form class="js-phoneSelectForm">
            <div class="form-group">
              <label for="phone_number">#{App.i18n.translateContent('Phone Number')}</label>
              <select name="phone_number" id="phone_number" class="form-control">#{phoneOptions}</select>
            </div>
            <div class="form-group">
              <button type="submit" class="btn btn--primary js-submit">#{App.i18n.translateContent('Complete Setup')}</button>
              <a href="#kc_extensions/kc_ringcentral_sms" class="btn btn--text">#{App.i18n.translateContent('Cancel')}</a>
            </div>
          </form>
        </div>
      </div>
    """

    @el.find('.js-phoneSelectForm').on('submit', @onSubmit)

  onSubmit: (e) =>
    e.preventDefault()
    @el.find('.js-submit').prop('disabled', true).text(App.i18n.translateContent('Creating channel…'))

    selectedPhone = @el.find('[name=phone_number]').val()

    @ajax(
      id:   'kc_ringcentral_sms_complete_setup'
      type: 'POST'
      url:  "#{@apiPath}/kc/ringcentral_sms_channels/complete_setup"
      data: JSON.stringify(phone_number: selectedPhone)
      contentType: 'application/json'
      success: (data) =>
        @navigate '#kc_extensions/kc_ringcentral_sms'
      error: (xhr) =>
        @el.find('.js-submit').prop('disabled', false).text(App.i18n.translateContent('Complete Setup'))
        data = xhr.responseJSON || {}
        @notify(type: 'error', msg: data.error || __('Failed to complete setup.'))
    )


# ---------------------------------------------------------------------------
# Route registration for phone selection page
# ---------------------------------------------------------------------------
App.Config.set('kc_extensions/kc_ringcentral_sms/select_phone', KcRingcentralSmsPhoneSelect, 'Routes')


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
