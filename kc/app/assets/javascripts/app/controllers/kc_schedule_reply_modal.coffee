# KC: Modal for selecting the datetime to schedule a reply.
#
# Extends App.ControllerModal with a single datetime field.
# On submit, calls @submitCallback with the selected datetime.
class App.KcScheduleReplyModal extends App.ControllerModal
  buttonClose: true
  buttonCancel: true
  buttonSubmit: __('Schedule')
  buttonClass: 'btn--primary'
  head: __('Schedule Reply')
  small: true

  events:
    'submit form':                        'submit'
    'click .js-submit:not(.is-disabled)': 'submit'
    'click .js-cancel':                   'cancel'
    'click .js-close':                    'cancel'

  content: ->
    configure_attributes = [
      {
        name:        'scheduled_at'
        display:     __('Send at')
        tag:         'datetime'
        null:        false
        future:      true
        placeholder: __('Select date and time')
      }
    ]

    @form = new App.ControllerForm(
      model:     { configure_attributes: configure_attributes }
      autofocus: true
    )

    @form.el

  onSubmit: (e) =>
    e.preventDefault()
    @formDisable(e)

    params = @formParams()

    errors = @form.validate(params)
    if !_.isEmpty(errors)
      @formEnable(e)
      @formValidate(form: @form.el, errors: errors)
      return false

    if !params.scheduled_at
      @formEnable(e)
      @formValidate(form: @form.el, errors: { scheduled_at: __('is required') })
      return false

    # Validate the datetime is in the future
    scheduledDate = new Date(params.scheduled_at)
    if scheduledDate <= new Date()
      @formEnable(e)
      @formValidate(form: @form.el, errors: { scheduled_at: __('must be in the future') })
      return false

    # Fire callback before close — the AJAX call is async (returns immediately),
    # so the modal animation completes well before the server responds and
    # taskReset() runs. This avoids the race condition where taskReset()
    # would orphan the modal backdrop.
    @submitCallback(params) if @submitCallback
    @close()
